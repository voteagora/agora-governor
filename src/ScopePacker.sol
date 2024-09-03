import {Packing} from "@openzeppelin/contracts/utils/Packing.sol";

library ScopePacker {
    type ScopeKey is bytes24;

    /**
     * @notice Generates the scope key defined as the contract address combined with the function selector
     * @param contractAddress Address of the contract to be enforced by the scope
     * @param selector A byte4 function selector on the contract to be enforced by the scope
     */
    function _pack(address contractAddress, bytes4 selector) external pure returns (ScopeKey) {
        bytes24 pack = Packing.pack_20_4(bytes20(contractAddress), selector);
        return ScopeKey.wrap(pack);
    }

    /**
     * @notice Unpacks the scope key into the constituent parts, i.e. contract address the first 20 bytes and the function selector as the last 4 bytes
     * @param self A byte24 key to be unpacked representing the key for a defined scope
     */
    function _unpack(ScopeKey self) external pure returns (address, bytes4) {
        bytes24 pack = ScopeKey.unwrap(self);
        return (
            address(Packing.extract_24_20(pack, 0)),
            Packing.extract_24_4(pack, 20)
        );
    }
}
