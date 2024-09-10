// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Timers} from "@openzeppelin/contracts-v4/utils/Timers.sol";
import {SafeCast} from "@openzeppelin/contracts-v4/utils/math/SafeCast.sol";
import {IVotes} from "@openzeppelin/contracts-v4/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts-v4/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts-v4/governance/IGovernor.sol";

import {GovernorCountingSimple} from "src/lib/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "src/lib/extensions/GovernorVotes.sol";
import {GovernorSettings} from "src/lib/extensions/GovernorSettings.sol";
import {GovernorTimelockControl} from "src/lib/extensions/GovernorTimelockControl.sol";
import {Governor} from "src/lib/Governor.sol";
import {VotingModule} from "src/modules/VotingModule.sol";
import {IProposalTypesConfigurator} from "src/interfaces/IProposalTypesConfigurator.sol";

contract AgoraGovernor is Governor, GovernorCountingSimple, GovernorVotes, GovernorSettings, GovernorTimelockControl {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address votingModule,
        bytes proposalData,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description,
        uint8 proposalType
    );
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address indexed votingModule,
        bytes proposalData,
        uint256 startBlock,
        uint256 endBlock,
        string description,
        uint8 proposalType
    );
    event ProposalTypeUpdated(uint256 indexed proposalId, uint8 proposalType);
    event ProposalDeadlineUpdated(uint256 proposalId, uint64 deadline);
    event AdminSet(address indexed oldAdmin, address indexed newAdmin);
    event ManagerSet(address indexed oldManager, address indexed newManager);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidProposalType(uint8 proposalType);
    error InvalidProposalId();

    /*//////////////////////////////////////////////////////////////
                               LIBRARIES
    //////////////////////////////////////////////////////////////*/

    using SafeCast for uint256;
    using Timers for Timers.BlockNumber;

    /*//////////////////////////////////////////////////////////////
                           IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 private constant GOVERNOR_VERSION = 1;

    // Max value of `quorum` and `approvalThreshold` in `ProposalType`
    uint16 public constant PERCENT_DIVISOR = 10_000;

    IProposalTypesConfigurator public PROPOSAL_TYPES_CONFIGURATOR;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address public admin;
    address public manager;

    mapping(address module => bool approved) public approvedModules;

    modifier onlyAdminOrTimelock() {
        require(
            msg.sender == admin || msg.sender == timelock(),
            "Only the admin or the governor timelock can call this function"
        );
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize the governor with the given parameters.
    /// @param _votingToken The governance token used for voting.
    /// @param _admin Admin address for the governor.
    /// @param _manager Manager address.
    /// @param _timelock The governance timelock.
    /// @param _proposalTypesConfigurator Proposal types configurator contract.
    /// @param _proposalTypes Initial proposal types to set.
    constructor(
        IVotes _votingToken,
        address _admin,
        address _manager,
        TimelockController _timelock,
        IProposalTypesConfigurator _proposalTypesConfigurator,
        IProposalTypesConfigurator.ProposalType[] memory _proposalTypes
    )
        Governor("Agora")
        GovernorVotes(_votingToken)
        GovernorSettings(6575, 46027, 0)
        GovernorTimelockControl(_timelock)
    {
        PROPOSAL_TYPES_CONFIGURATOR = _proposalTypesConfigurator;
        PROPOSAL_TYPES_CONFIGURATOR.initialize(address(this), _proposalTypes);

        admin = _admin;
        manager = _manager;
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the quorum for a `proposalId`, in terms of number of votes: `supply * numerator / denominator`.
    /// @dev Supply is calculated at the proposal snapshot timepoint.
    /// @dev Quorum value is derived from `PROPOSAL_TYPES_CONFIGURATOR`.
    function quorum(uint256 proposalId) public view virtual override returns (uint256) {
        uint256 snapshotBlock = proposalSnapshot(proposalId);
        uint256 supply = token.getPastTotalSupply(snapshotBlock);

        uint8 proposalTypeId = _proposals[proposalId].proposalType;

        return (supply * PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalTypeId).quorum) / PERCENT_DIVISOR;
    }

    /// @dev Updated version in which quorum is based on `proposalId` instead of snapshot block.
    function _quorumReached(uint256 proposalId)
        internal
        view
        virtual
        override(GovernorCountingSimple, Governor)
        returns (bool)
    {
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = proposalVotes(proposalId);

        return quorum(proposalId) <= againstVotes + forVotes + abstainVotes;
    }

    /// @dev Added logic based on approval voting threshold to determine if vote has succeeded.
    function _voteSucceeded(uint256 proposalId)
        internal
        view
        virtual
        override(GovernorCountingSimple, Governor)
        returns (bool voteSucceeded)
    {
        ProposalCore storage proposal = _proposals[proposalId];

        address votingModule = proposal.votingModule;
        if (votingModule != address(0)) {
            if (!VotingModule(votingModule)._voteSucceeded(proposalId)) {
                return false;
            }
        }

        uint256 approvalThreshold = PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposal.proposalType).approvalThreshold;

        if (approvalThreshold == 0) return true;

        ProposalVote storage proposalVote = _proposalVotes[proposalId];
        uint256 forVotes = proposalVote.forVotes;
        uint256 totalVotes = forVotes + proposalVote.againstVotes;

        if (totalVotes != 0) {
            voteSucceeded = (forVotes * PERCENT_DIVISOR) / totalVotes >= approvalThreshold;
        }
    }

    /// @notice Returns the proposal type of a proposal.
    /// @param proposalId The id of the proposal.
    function getProposalType(uint256 proposalId) external view returns (uint8) {
        return _proposals[proposalId].proposalType;
    }

    /// @dev See {IGovernor-COUNTING_MODE}.
    /// Params encoding:
    /// - modules = custom external params depending on module used
    function COUNTING_MODE() public pure virtual override(GovernorCountingSimple, IGovernor) returns (string memory) {
        return "support=bravo&quorum=against,for,abstain&params=modules";
    }

    /// @dev Returns the current version of the governor.
    function VERSION() public pure virtual returns (uint256) {
        return GOVERNOR_VERSION;
    }

    /// @notice Calculate `proposalId` hashing similarly to `hashProposal` but based on `module` and `proposalData`.
    /// See {IGovernor-hashProposal}.
    /// @param module The address of the voting module to use for this proposal.
    /// @param proposalData The proposal data to pass to the voting module.
    /// @param descriptionHash The hash of the proposal description.
    /// @return The id of the proposal.
    function hashProposalWithModule(address module, bytes memory proposalData, bytes32 descriptionHash)
        public
        view
        virtual
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(address(this), module, proposalData, descriptionHash)));
    }

    /// @inheritdoc GovernorSettings
    function proposalThreshold() public view override(GovernorSettings, Governor) returns (uint256) {
        return GovernorSettings.proposalThreshold();
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return GovernorTimelockControl._executor();
    }

    /// @inheritdoc GovernorTimelockControl
    function state(uint256 proposalId)
        public
        view
        virtual
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return GovernorTimelockControl.state(proposalId);
    }

    /// @inheritdoc GovernorTimelockControl
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return GovernorTimelockControl.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                           WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Approve or reject a voting module. Only the admin or timelock can call this function.
    /// @param module The address of the voting module to approve or reject.
    /// @param approved Whether to approve or reject the voting module.
    function setModuleApproval(address module, bool approved) external onlyAdminOrTimelock {
        approvedModules[module] = approved;
    }

    /// @notice Set the deadline for a proposal. Only the admin or timelock can call this function.
    /// @param proposalId The id of the proposal.
    /// @param deadline The new deadline for the proposal.
    function setProposalDeadline(uint256 proposalId, uint64 deadline) external onlyAdminOrTimelock {
        _proposals[proposalId].voteEnd.setDeadline(deadline);
        emit ProposalDeadlineUpdated(proposalId, deadline);
    }

    /// @inheritdoc GovernorSettings
    function setVotingDelay(uint256 newVotingDelay) public override onlyAdminOrTimelock {
        _setVotingDelay(newVotingDelay);
    }

    /// @inheritdoc GovernorSettings
    function setVotingPeriod(uint256 newVotingPeriod) public override onlyAdminOrTimelock {
        _setVotingPeriod(newVotingPeriod);
    }

    /// @inheritdoc GovernorSettings
    function setProposalThreshold(uint256 newProposalThreshold) public override onlyAdminOrTimelock {
        _setProposalThreshold(newProposalThreshold);
    }

    /// @notice Set the admin address. Only the admin or timelock can call this function.
    /// @param _newAdmin The new admin address.
    function setAdmin(address _newAdmin) external onlyAdminOrTimelock {
        emit AdminSet(admin, _newAdmin);
        admin = _newAdmin;
    }

    /// @notice Set the manager address. Only the admin or timelock can call this function.
    /// @param _newManager The new manager address.
    function setManager(address _newManager) external onlyAdminOrTimelock {
        emit ManagerSet(manager, _newManager);
        manager = _newManager;
    }

    /// @dev Updated internal vote casting mechanism which delegates counting logic to voting module,
    /// in addition to executing standard `_countVote`. See {IGovernor-_castVote}.
    function _castVote(uint256 proposalId, address account, uint8 support, string memory reason, bytes memory params)
        internal
        virtual
        override
        returns (uint256 weight)
    {
        require(state(proposalId) == ProposalState.Active, "Governor: vote not currently active");

        weight = _getVotes(account, _proposals[proposalId].voteStart.getDeadline(), "");

        _countVote(proposalId, account, support, weight, params);

        address votingModule = _proposals[proposalId].votingModule;

        if (votingModule != address(0)) {
            VotingModule(votingModule)._countVote(proposalId, account, support, weight, params);
        }

        if (params.length == 0) {
            emit VoteCast(account, proposalId, support, weight, reason);
        } else {
            emit VoteCastWithParams(account, proposalId, support, weight, reason, params);
        }
    }

    /// @inheritdoc Governor
    /// @dev Updated version in which default `proposalType` is set to 0.
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override(IGovernor, Governor) returns (uint256) {
        return propose(targets, values, calldatas, description, 0);
    }

    /// @notice Propose a new proposal. Only the manager or an address with votes above the proposal threshold can propose.
    /// See {IGovernor-propose}.
    /// @dev Updated version of `propose` in which `proposalType` is set and checked.
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        uint8 proposalType
    ) public virtual returns (uint256 proposalId) {
        address proposer = _msgSender();
        require(_isValidDescriptionForProposer(proposer, description), "Governor: proposer restricted");

        uint256 currentTimepoint = clock();
        if (proposer != manager) {
            require(
                getVotes(proposer, currentTimepoint - 1) >= proposalThreshold(),
                "Governor: proposer votes below proposal threshold"
            );
        }

        proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));

        require(targets.length == values.length, "Governor: invalid proposal length");
        require(targets.length == calldatas.length, "Governor: invalid proposal length");
        require(targets.length > 0, "Governor: empty proposal");
        require(_proposals[proposalId].voteStart == 0, "Governor: proposal already exists");

        // Revert if `proposalType` is unset or requires module
        if (
            bytes(PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalType).name).length == 0
                || PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalType).module != address(0)
        ) {
            revert InvalidProposalType(proposalType);
        }

        uint256 snapshot = currentTimepoint + votingDelay();
        uint256 deadline = snapshot + votingPeriod();

        _proposals[proposalId] = ProposalCore({
            proposer: proposer,
            voteStart: SafeCast.toUint64(snapshot),
            voteEnd: SafeCast.toUint64(deadline),
            executed: false,
            canceled: false,
            votingModule: address(0),
            proposalType: proposalType,
            __gap_unused0: 0,
            __gap_unused1: 0
        });

        emit ProposalCreated(
            proposalId,
            proposer,
            targets,
            values,
            new string[](targets.length),
            calldatas,
            snapshot,
            deadline,
            description,
            proposalType
        );
    }

    /// @notice Propose a new proposal using a custom voting module. Only the manager or an address with votes above the
    /// proposal threshold can propose. Uses the default proposal type.
    /// @param module The address of the voting module to use for this proposal.
    /// @param proposalData The proposal data to pass to the voting module.
    /// @param description The description of the proposal.
    /// @return The id of the proposal.
    function proposeWithModule(VotingModule module, bytes memory proposalData, string memory description)
        public
        virtual
        returns (uint256)
    {
        return proposeWithModule(module, proposalData, description, 0);
    }

    /// @notice Propose a new proposal using a custom voting module. Only the manager or an address with votes above the
    /// proposal threshold can propose.
    /// @param module The address of the voting module to use for this proposal.
    /// @param proposalData The proposal data to pass to the voting module.
    /// @param description The description of the proposal.
    /// @param proposalType The type of the proposal.
    /// @dev Updated version in which `proposalType` is set and checked.
    /// @return proposalId The id of the proposal.
    function proposeWithModule(
        VotingModule module,
        bytes memory proposalData,
        string memory description,
        uint8 proposalType
    ) public virtual returns (uint256 proposalId) {
        require(approvedModules[address(module)], "Governor: module not approved");

        address proposer = _msgSender();
        require(_isValidDescriptionForProposer(proposer, description), "Governor: proposer restricted");

        uint256 currentTimepoint = clock();
        if (proposer != manager) {
            require(
                getVotes(proposer, currentTimepoint - 1) >= proposalThreshold(),
                "Governor: proposer votes below proposal threshold"
            );
        }

        bytes32 descriptionHash = keccak256(bytes(description));
        proposalId = hashProposalWithModule(address(module), proposalData, descriptionHash);

        require(_proposals[proposalId].voteStart == 0, "Governor: proposal already exists");

        // Revert if `proposalType` is unset or requires module
        if (
            bytes(PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalType).name).length == 0
                || PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalType).module != address(module)
        ) {
            revert InvalidProposalType(proposalType);
        }

        uint256 snapshot = currentTimepoint + votingDelay();
        uint256 deadline = snapshot + votingPeriod();

        _proposals[proposalId] = ProposalCore({
            proposer: proposer,
            voteStart: SafeCast.toUint64(snapshot),
            voteEnd: SafeCast.toUint64(deadline),
            executed: false,
            canceled: false,
            votingModule: address(0),
            proposalType: proposalType,
            __gap_unused0: 0,
            __gap_unused1: 0
        });

        module.propose(proposalId, proposalData, descriptionHash);

        emit ProposalCreated(
            proposalId, proposer, address(module), proposalData, snapshot, deadline, description, proposalType
        );
    }

    /// @notice Allows admin or timelock to modify the proposalType of a proposal, in case it was set incorrectly.
    /// @param proposalId The id of the proposal.
    /// @param proposalType The new proposal type.
    function editProposalType(uint256 proposalId, uint8 proposalType) external onlyAdminOrTimelock {
        if (proposalSnapshot(proposalId) == 0) revert InvalidProposalId();

        // Revert if `proposalType` is unset
        if (bytes(PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalType).name).length == 0) {
            revert InvalidProposalType(proposalType);
        }

        _proposals[proposalId].proposalType = proposalType;

        emit ProposalTypeUpdated(proposalId, proposalType);
    }

    /// @notice Cancel a proposal. Only the admin or timelock can call this function.
    /// See {Governor-_cancel}.
    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public override(IGovernor, Governor) returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        require(state(proposalId) == ProposalState.Pending, "Governor: too late to cancel");
        address caller = _msgSender();
        require(
            caller == admin || caller == timelock() || caller == _proposals[proposalId].proposer,
            "Governor: only admin, governor timelock, or proposer can cancel"
        );
        return _cancel(targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return GovernorTimelockControl._cancel(targets, values, calldatas, descriptionHash);
    }

    /// @notice Cancel a proposal with a custom voting module. See {Governor-_cancel}.
    /// @param module The address of the voting module to use for this proposal.
    /// @param proposalData The proposal data to pass to the voting module.
    /// @param descriptionHash The hash of the proposal description.
    /// @return The id of the proposal.
    function cancelWithModule(VotingModule module, bytes memory proposalData, bytes32 descriptionHash)
        public
        virtual
        onlyAdminOrTimelock
        returns (uint256)
    {
        uint256 proposalId = hashProposalWithModule(address(module), proposalData, descriptionHash);
        ProposalState status = state(proposalId);

        require(status != ProposalState.Canceled && status != ProposalState.Executed, "Governor: proposal not active");
        _proposals[proposalId].canceled = true;

        emit ProposalCanceled(proposalId);

        // Code from GovernorTimelockControl._cancel
        if (_timelockIds[proposalId] != 0) {
            _timelock.cancel(_timelockIds[proposalId]);
            delete _timelockIds[proposalId];
        }

        return proposalId;
    }

    /// @inheritdoc GovernorTimelockControl
    function queue(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash)
        public
        override
        returns (uint256)
    {
        return super.queue(targets, values, calldatas, descriptionHash);
    }

    /// @notice Queue a proposal with a custom voting module. See {GovernorTimelockControl-queue}.
    function queueWithModule(VotingModule module, bytes memory proposalData, bytes32 descriptionHash)
        public
        returns (uint256)
    {
        uint256 proposalId = hashProposalWithModule(address(module), proposalData, descriptionHash);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            module._formatExecuteParams(proposalId, proposalData);

        require(state(proposalId) == ProposalState.Succeeded, "Governor: proposal not successful");

        uint256 delay = _timelock.getMinDelay();
        _timelockIds[proposalId] = _timelock.hashOperationBatch(targets, values, calldatas, 0, descriptionHash);
        _timelock.scheduleBatch(targets, values, calldatas, 0, descriptionHash, delay);

        emit ProposalQueued(proposalId, block.timestamp + delay);

        return proposalId;
    }

    /// @inheritdoc Governor
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable override(IGovernor, Governor) returns (uint256) {
        return super.execute(targets, values, calldatas, descriptionHash);
    }

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        return GovernorTimelockControl._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    /// Executes a proposal via a custom voting module. See {IGovernor-execute}.
    ///
    /// @param module The address of the voting module to use for this proposal.
    /// @param proposalData The proposal data to pass to the voting module.
    /// @param descriptionHash The hash of the proposal description.
    function executeWithModule(VotingModule module, bytes memory proposalData, bytes32 descriptionHash)
        public
        payable
        virtual
        returns (uint256)
    {
        uint256 proposalId = hashProposalWithModule(address(module), proposalData, descriptionHash);

        ProposalState status = state(proposalId);
        require(
            status == ProposalState.Succeeded || status == ProposalState.Queued, "Governor: proposal not successful"
        );
        _proposals[proposalId].executed = true;

        emit ProposalExecuted(proposalId);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            module._formatExecuteParams(proposalId, proposalData);

        _beforeExecute(proposalId, targets, values, calldatas, descriptionHash);
        _execute(proposalId, targets, values, calldatas, descriptionHash);
        _afterExecute(proposalId, targets, values, calldatas, descriptionHash);

        return proposalId;
    }
}
