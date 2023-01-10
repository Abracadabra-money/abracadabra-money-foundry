// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ICauldronV1 {
    function accrue() external;

    function withdrawFees() external;

    function accrueInfo() external view returns (uint64, uint128);

    function setFeeTo(address newFeeTo) external;

    function feeTo() external returns (address);

    function masterContract() external returns (ICauldronV1);

    function bentoBox() external view returns (address);
}
