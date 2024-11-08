// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {TimersUpgradeable} from "@openzeppelin/contracts-upgradeable-v4/utils/TimersUpgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable-v4/utils/math/SafeCastUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable-v4/proxy/utils/Initializable.sol";
import {TimelockControllerUpgradeable} from
    "@openzeppelin/contracts-upgradeable-v4/governance/TimelockControllerUpgradeable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable-v4/utils/AddressUpgradeable.sol";
import {GovernorCountingSimpleUpgradeableV2} from "src/lib/openzeppelin/v2/GovernorCountingSimpleUpgradeableV2.sol";
import {IGovernorUpgradeable} from "src/lib/openzeppelin/v2/GovernorUpgradeableV2.sol";
import {GovernorUpgradeableV2} from "src/lib/openzeppelin/v2/GovernorUpgradeableV2.sol";
import {GovernorVotesUpgradeableV2} from "src/lib/openzeppelin/v2/GovernorVotesUpgradeableV2.sol";
import {GovernorSettingsUpgradeableV2} from "src/lib/openzeppelin/v2/GovernorSettingsUpgradeableV2.sol";
import {GovernorTimelockControlUpgradeableV2} from "src/lib/openzeppelin/v2/GovernorTimelockControlUpgradeableV2.sol";
import {IProposalTypesConfigurator} from "src/interfaces/IProposalTypesConfigurator.sol";
import {ProposalTypesConfigurator} from "src/ProposalTypesConfigurator.sol";
import {VotingModule} from "src/modules/VotingModule.sol";
import {IVotingToken} from "src/interfaces/IVotingToken.sol";

/// @custom:security-contact security@voteagora.com
contract AgoraGovernor is
    Initializable,
    GovernorUpgradeableV2,
    GovernorCountingSimpleUpgradeableV2,
    GovernorVotesUpgradeableV2,
    GovernorSettingsUpgradeableV2,
    GovernorTimelockControlUpgradeableV2
{
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

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
        uint8 proposalTypeId
    );
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address indexed votingModule,
        bytes proposalData,
        uint256 startBlock,
        uint256 endBlock,
        string description,
        uint8 proposalTypeId
    );
    event ProposalTypeUpdated(uint256 indexed proposalId, uint8 proposalTypeId);
    event ProposalDeadlineUpdated(uint256 proposalId, uint64 deadline);
    event AdminSet(address indexed oldAdmin, address indexed newAdmin);
    event ManagerSet(address indexed oldManager, address indexed newManager);

    enum SupplyType {
        Total,
        Votable
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidProposalType(uint8 proposalTypeId);
    error InvalidProposalId();
    error InvalidProposalLength();
    error InvalidEmptyProposal();
    error InvalidVotesBelowThreshold();
    error InvalidProposalExists();
    error InvalidRelayTarget(address target);
    error NotAdminOrTimelock();

    /*//////////////////////////////////////////////////////////////
                               LIBRARIES
    //////////////////////////////////////////////////////////////*/

    using SafeCastUpgradeable for uint256;
    using TimersUpgradeable for TimersUpgradeable.BlockNumber;

    /*//////////////////////////////////////////////////////////////
                           IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 private constant GOVERNOR_VERSION = 1;

    /// @notice Max value of `quorum` and `approvalThreshold` in `ProposalType`
    uint16 public constant PERCENT_DIVISOR = 10_000;

    IProposalTypesConfigurator public PROPOSAL_TYPES_CONFIGURATOR;

    SupplyType public SUPPLY_TYPE;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address public admin;
    address public manager;

    mapping(address module => bool approved) public approvedModules;

    modifier onlyAdminOrTimelock() {
        address sender = _msgSender();
        if (sender != admin && sender != timelock()) revert NotAdminOrTimelock();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the governor with the given parameters.
     * @param _votingToken The governance token used for voting.
     * @param _supplyType The type of supply to use for voting calculations.
     * @param _admin Admin address for the governor.
     * @param _manager Manager address.
     * @param _timelock The governance timelock.
     * @param _proposalTypes Initial proposal types to set.
     */
    function initialize(
        IVotingToken _votingToken,
        SupplyType _supplyType,
        address _admin,
        address _manager,
        TimelockControllerUpgradeable _timelock,
        IProposalTypesConfigurator.ProposalType[] calldata _proposalTypes
    ) public initializer {
        IProposalTypesConfigurator _proposalTypesConfigurator = new ProposalTypesConfigurator();
        PROPOSAL_TYPES_CONFIGURATOR = _proposalTypesConfigurator;
        SUPPLY_TYPE = _supplyType;

        PROPOSAL_TYPES_CONFIGURATOR.initialize(address(this), _proposalTypes);

        __Governor_init("Agora");
        __GovernorCountingSimple_init();
        __GovernorVotes_init(_votingToken);
        __GovernorSettings_init({initialVotingDelay: 6575, initialVotingPeriod: 46027, initialProposalThreshold: 0});
        __GovernorTimelockControl_init(_timelock);

        admin = _admin;
        manager = _manager;
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the quorum for a `proposalId`, in terms of number of votes: `supply * numerator / denominator`.
     * @dev Supply is calculated at the proposal snapshot timepoint.
     * @dev Quorum value is derived from `PROPOSAL_TYPES_CONFIGURATOR`.
     */
    function quorum(uint256 proposalId) public view virtual override returns (uint256) {
        uint256 snapshotBlock = proposalSnapshot(proposalId);
        uint256 supply;
        if (SUPPLY_TYPE == SupplyType.Total) {
            supply = token.getPastTotalSupply(snapshotBlock);
        } else {
            supply = token.getPastVotableSupply(snapshotBlock);
        }

        uint8 proposalTypeId = _proposals[proposalId].proposalType;

        return (supply * PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalTypeId).quorum) / PERCENT_DIVISOR;
    }

    /**
     * @dev Updated version in which quorum is based on `proposalId` instead of snapshot block.
     */
    function _quorumReached(uint256 proposalId)
        internal
        view
        virtual
        override(GovernorCountingSimpleUpgradeableV2, GovernorUpgradeableV2)
        returns (bool)
    {
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = proposalVotes(proposalId);

        return quorum(proposalId) <= againstVotes + forVotes + abstainVotes;
    }

    /**
     * @dev Added logic based on approval voting threshold to determine if vote has succeeded.
     */
    function _voteSucceeded(uint256 proposalId)
        internal
        view
        virtual
        override(GovernorCountingSimpleUpgradeableV2, GovernorUpgradeableV2)
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

    /**
     * @notice Returns the proposal type of a proposal.
     * @param proposalId The id of the proposal.
     */
    function getProposalType(uint256 proposalId) external view returns (uint8) {
        return _proposals[proposalId].proposalType;
    }

    /**
     * @dev See {IGovernor-COUNTING_MODE}.
     * Params encoding:
     * - modules = custom external params depending on module used
     */
    function COUNTING_MODE()
        public
        pure
        virtual
        override(GovernorCountingSimpleUpgradeableV2, IGovernorUpgradeable)
        returns (string memory)
    {
        return "support=bravo&quorum=against,for,abstain&params=modules";
    }

    /**
     * @dev Returns the current version of the governor.
     */
    function VERSION() public pure virtual returns (uint256) {
        return GOVERNOR_VERSION;
    }

    /**
     * @notice Calculate `proposalId` hashing similarly to `hashProposal` but based on `module` and `proposalData`.
     * See {IGovernor-hashProposal}.
     * @param module The address of the voting module to use for this proposal.
     * @param proposalData The proposal data to pass to the voting module.
     * @param descriptionHash The hash of the proposal description.
     * @return The id of the proposal.
     */
    function hashProposalWithModule(address module, bytes memory proposalData, bytes32 descriptionHash)
        public
        view
        virtual
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(address(this), module, proposalData, descriptionHash)));
    }

    /**
     * @inheritdoc GovernorSettingsUpgradeableV2
     */
    function proposalThreshold()
        public
        view
        override(GovernorSettingsUpgradeableV2, GovernorUpgradeableV2)
        returns (uint256)
    {
        return GovernorSettingsUpgradeableV2.proposalThreshold();
    }

    function _executor()
        internal
        view
        override(GovernorUpgradeableV2, GovernorTimelockControlUpgradeableV2)
        returns (address)
    {
        return GovernorTimelockControlUpgradeableV2._executor();
    }

    /**
     * @inheritdoc GovernorTimelockControlUpgradeableV2
     */
    function state(uint256 proposalId)
        public
        view
        virtual
        override(GovernorUpgradeableV2, GovernorTimelockControlUpgradeableV2)
        returns (ProposalState)
    {
        return GovernorTimelockControlUpgradeableV2.state(proposalId);
    }

    /**
     * @inheritdoc GovernorTimelockControlUpgradeableV2
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(GovernorUpgradeableV2, GovernorTimelockControlUpgradeableV2)
        returns (bool)
    {
        return GovernorTimelockControlUpgradeableV2.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                           WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Approve or reject a voting module. Only the admin or timelock can call this function.
     * @param module The address of the voting module to approve or reject.
     * @param approved Whether to approve or reject the voting module.
     */
    function setModuleApproval(address module, bool approved) external onlyAdminOrTimelock {
        approvedModules[module] = approved;
    }

    /**
     * @notice Set the deadline for a proposal. Only the admin or timelock can call this function.
     * @param proposalId The id of the proposal.
     * @param deadline The new deadline for the proposal.
     */
    function setProposalDeadline(uint256 proposalId, uint64 deadline) external onlyAdminOrTimelock {
        _proposals[proposalId].voteEnd.setDeadline(deadline);
        emit ProposalDeadlineUpdated(proposalId, deadline);
    }

    /**
     * @inheritdoc GovernorSettingsUpgradeableV2
     */
    function setVotingDelay(uint256 newVotingDelay) public override onlyAdminOrTimelock {
        _setVotingDelay(newVotingDelay);
    }

    /**
     * @inheritdoc GovernorSettingsUpgradeableV2
     */
    function setVotingPeriod(uint256 newVotingPeriod) public override onlyAdminOrTimelock {
        _setVotingPeriod(newVotingPeriod);
    }

    /**
     * @inheritdoc GovernorSettingsUpgradeableV2
     */
    function setProposalThreshold(uint256 newProposalThreshold) public override onlyAdminOrTimelock {
        _setProposalThreshold(newProposalThreshold);
    }

    /**
     * @notice Set the admin address. Only the admin or timelock can call this function.
     * @param _newAdmin The new admin address.
     */
    function setAdmin(address _newAdmin) external onlyAdminOrTimelock {
        emit AdminSet(admin, _newAdmin);
        admin = _newAdmin;
    }

    /**
     * @notice Set the manager address. Only the admin or timelock can call this function.
     * @param _newManager The new manager address.
     */
    function setManager(address _newManager) external onlyAdminOrTimelock {
        emit ManagerSet(manager, _newManager);
        manager = _newManager;
    }

    /**
     * @dev Updated internal vote casting mechanism which delegates counting logic to voting module,
     * in addition to executing standard `_countVote`. See {IGovernor-_castVote}.
     */
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

    /**
     * @inheritdoc GovernorUpgradeableV2
     */
    function relay(address target, uint256 value, bytes calldata data)
        external
        payable
        virtual
        override(GovernorUpgradeableV2)
        onlyGovernance
    {
        if (approvedModules[target]) revert InvalidRelayTarget(target);
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        AddressUpgradeable.verifyCallResult(success, returndata, "Governor: relay reverted without message");
    }

    /**
     * @inheritdoc GovernorUpgradeableV2
     * @dev Updated version in which default `proposalType` is set to 0.
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override(IGovernorUpgradeable, GovernorUpgradeableV2) returns (uint256) {
        return propose(targets, values, calldatas, description, 0);
    }

    /**
     * @notice Propose a new proposal. Only the manager or an address with votes above the proposal threshold can propose.
     * See {IGovernor-propose}.
     * @dev Updated version of `propose` in which `proposalType` is set and checked.
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        uint8 proposalTypeId
    ) public virtual returns (uint256 proposalId) {
        address proposer = _msgSender();
        if (proposer != manager && getVotes(proposer, block.number - 1) < proposalThreshold()) {
            revert InvalidVotesBelowThreshold();
        }

        if (targets.length != values.length) revert InvalidProposalLength();
        if (targets.length != calldatas.length) revert InvalidProposalLength();
        if (targets.length == 0) revert InvalidEmptyProposal();

        // Revert if `proposalType` is unset or requires module
        if (
            bytes(PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalTypeId).name).length == 0
                || PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalTypeId).module != address(0)
        ) {
            revert InvalidProposalType(proposalTypeId);
        }

        PROPOSAL_TYPES_CONFIGURATOR.validateProposalData(targets, calldatas, proposalTypeId);

        proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));

        ProposalCore storage proposal = _proposals[proposalId];
        if (!proposal.voteStart.isUnset()) revert InvalidProposalExists();

        uint64 snapshot = block.number.toUint64() + votingDelay().toUint64();
        uint64 deadline = snapshot + votingPeriod().toUint64();

        proposal.voteStart.setDeadline(snapshot);
        proposal.voteEnd.setDeadline(deadline);
        proposal.proposalType = proposalTypeId;
        proposal.proposer = proposer;

        emit ProposalCreated(
            proposalId,
            _msgSender(),
            targets,
            values,
            new string[](targets.length),
            calldatas,
            snapshot,
            deadline,
            description,
            proposalTypeId
        );
    }

    /**
     * @notice Propose a new proposal using a custom voting module. Only the manager or an address with votes above the
     * proposal threshold can propose. Uses the default proposal type.
     * @param module The address of the voting module to use for this proposal.
     * @param proposalData The proposal data to pass to the voting module.
     * @param description The description of the proposal.
     * @return The id of the proposal.
     */
    function proposeWithModule(VotingModule module, bytes memory proposalData, string memory description)
        public
        virtual
        returns (uint256)
    {
        return proposeWithModule(module, proposalData, description, 0);
    }

    /**
     * @notice Propose a new proposal using a custom voting module. Only the manager or an address with votes above the
     * proposal threshold can propose.
     * @param module The address of the voting module to use for this proposal.
     * @param proposalData The proposal data to pass to the voting module.
     * @param description The description of the proposal.
     * @param proposalTypeId The type of the proposal.
     * @dev Updated version in which `proposalTypeId` is set and checked.
     * @return proposalId The id of the proposal.
     */
    function proposeWithModule(
        VotingModule module,
        bytes memory proposalData,
        string memory description,
        uint8 proposalTypeId
    ) public virtual returns (uint256 proposalId) {
        address proposer = _msgSender();
        if (proposer != manager) {
            if (getVotes(proposer, block.number - 1) < proposalThreshold()) revert InvalidVotesBelowThreshold();
        }

        require(approvedModules[address(module)], "Governor: module not approved");

        // Revert if `proposalTypeId` is unset or doesn't match module
        if (
            bytes(PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalTypeId).name).length == 0
                || PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalTypeId).module != address(module)
        ) {
            revert InvalidProposalType(proposalTypeId);
        }

        bytes32 descriptionHash = keccak256(bytes(description));

        proposalId = hashProposalWithModule(address(module), proposalData, descriptionHash);

        ProposalCore storage proposal = _proposals[proposalId];
        if (!proposal.voteStart.isUnset()) revert InvalidProposalExists();

        uint64 snapshot = block.number.toUint64() + votingDelay().toUint64();
        uint64 deadline = snapshot + votingPeriod().toUint64();

        proposal.voteStart.setDeadline(snapshot);
        proposal.voteEnd.setDeadline(deadline);
        proposal.votingModule = address(module);
        proposal.proposalType = proposalTypeId;
        proposal.proposer = proposer;

        module.propose(proposalId, proposalData, descriptionHash);

        emit ProposalCreated(
            proposalId, proposer, address(module), proposalData, snapshot, deadline, description, proposalTypeId
        );
    }

    /**
     * @notice Allows admin or timelock to modify the `proposalTypeId` of a proposal, in case it was set incorrectly.
     * @param proposalId The id of the proposal.
     * @param proposalTypeId The new proposal type.
     */
    function editProposalType(uint256 proposalId, uint8 proposalTypeId) external onlyAdminOrTimelock {
        if (proposalSnapshot(proposalId) == 0) revert InvalidProposalId();

        // Revert if `proposalTypeId` is unset or the proposal has a different voting module
        if (
            bytes(PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalTypeId).name).length == 0
                || PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalTypeId).module != _proposals[proposalId].votingModule
        ) {
            revert InvalidProposalType(proposalTypeId);
        }

        _proposals[proposalId].proposalType = proposalTypeId;

        emit ProposalTypeUpdated(proposalId, proposalTypeId);
    }

    /**
     * @notice Cancel a proposal. Only the admin, timelock, or proposer can call this function.
     * See {GovernorUpgradeableV2-_cancel}.
     */
    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        address sender = _msgSender();
        require(
            sender == admin || sender == timelock() || sender == _proposals[proposalId].proposer,
            "Governor: only admin, governor timelock, or proposer can cancel"
        );

        return _cancel(targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeableV2, GovernorTimelockControlUpgradeableV2) returns (uint256) {
        return GovernorTimelockControlUpgradeableV2._cancel(targets, values, calldatas, descriptionHash);
    }

    /**
     * @notice Cancel a proposal with a custom voting module. See {GovernorUpgradeableV2-_cancel}.
     * @param module The address of the voting module to use for this proposal.
     * @param proposalData The proposal data to pass to the voting module.
     * @param descriptionHash The hash of the proposal description.
     * @return The id of the proposal.
     */
    function cancelWithModule(VotingModule module, bytes memory proposalData, bytes32 descriptionHash)
        public
        virtual
        returns (uint256)
    {
        uint256 proposalId = hashProposalWithModule(address(module), proposalData, descriptionHash);
        address sender = _msgSender();
        require(
            sender == admin || sender == timelock() || sender == _proposals[proposalId].proposer,
            "Governor: only admin, governor timelock, or proposer can cancel"
        );

        ProposalState status = state(proposalId);

        require(
            status != ProposalState.Canceled && status != ProposalState.Expired && status != ProposalState.Executed,
            "Governor: proposal not active"
        );

        _proposals[proposalId].canceled = true;

        emit ProposalCanceled(proposalId);

        // Code from GovernorTimelockControlUpgradeableV2._cancel
        if (_timelockIds[proposalId] != 0) {
            _timelock.cancel(_timelockIds[proposalId]);
            delete _timelockIds[proposalId];
        }

        return proposalId;
    }

    /**
     * @inheritdoc GovernorTimelockControlUpgradeableV2
     */
    function queue(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash)
        public
        override
        returns (uint256)
    {
        return super.queue(targets, values, calldatas, descriptionHash);
    }

    /**
     * @notice Queue a proposal with a custom voting module. See {GovernorTimelockControlUpgradeableV2-queue}.
     */
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

    /**
     * @inheritdoc GovernorUpgradeableV2
     */
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable override(IGovernorUpgradeable, GovernorUpgradeableV2) returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);

        ProposalState status = state(proposalId);
        require(status == ProposalState.Queued, "Governor: proposal not queued");
        _proposals[proposalId].executed = true;

        emit ProposalExecuted(proposalId);

        _beforeExecute(proposalId, targets, values, calldatas, descriptionHash);
        _execute(proposalId, targets, values, calldatas, descriptionHash);
        _afterExecute(proposalId, targets, values, calldatas, descriptionHash);

        return proposalId;
    }

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeableV2, GovernorTimelockControlUpgradeableV2) {
        return GovernorTimelockControlUpgradeableV2._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    /**
     * Executes a proposal via a custom voting module. See {IGovernor-execute}.
     *
     * @param module The address of the voting module to use for this proposal.
     * @param proposalData The proposal data to pass to the voting module.
     * @param descriptionHash The hash of the proposal description.
     */
    function executeWithModule(VotingModule module, bytes memory proposalData, bytes32 descriptionHash)
        public
        payable
        virtual
        returns (uint256)
    {
        uint256 proposalId = hashProposalWithModule(address(module), proposalData, descriptionHash);

        ProposalState status = state(proposalId);
        require(status == ProposalState.Queued, "Governor: proposal not queued");
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
