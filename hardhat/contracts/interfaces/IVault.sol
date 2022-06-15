// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/*
@title The interface for the vault contract
*/
interface IVault {
    // #### Struct definitions
    struct VaultDetails {
        bool initialised; // Boolean of whether the vault is initialised
        bool depositsWithdrawn; // Boolean of whether deposits is withdrawn
        uint256 collateralAmount;  // The amount of collateral held by the vault contract
        uint256 debtAmount; // The amount of stable coin that was minted against the collateral
    }

    // #### Event definitions
    event Deposit(bytes32 commitment, uint32 leafIndex, uint256 timestamp);
    event Borrow(address recipient, bytes32 nullifierHash, uint256 borrowAmount);
    event Withdrawal(address recipient, bytes32 nullifierHash, uint256 amountToWithdraw, uint256 repaymentAmount);
    
    // #### Function definitions

    /**
    @notice Allows a user to deposit ETH collateral in exchange for some amount of stablecoin
    @param _commitment The note commitment, which is PedersenHash(nullifier + secret)
     */
    function deposit(bytes32 _commitment) payable external;

    /**
    @notice Allows a user to take out some amount of stablecoin with their ETH deposits as collateral 
    @param a Part of zk proof
    @param b Part of zk proof
    @param c Part of zk proof
    @param _root The merkle root of all deposits in the contract
    @param _nullifierHash The hash of unique deposit nullifier to prevent double spends
    @param _recipient The recipient address
    @param _borrowAmount The amount of stablecoins the user will borrow
     */
    function borrow(
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c,
        bytes32 _root,
        bytes32 _nullifierHash,
        address payable _recipient,
        uint256 _borrowAmount
    ) external;
    
    /**
    @notice Allows a user to withdraw up to collaterisation ratio of the collateral they have on deposit
    @dev This cannot allow a user to withdraw more than they put in
    @param a Part of zk proof
    @param b Part of zk proof
    @param c Part of zk proof
    @param _root The merkle root of all deposits in the contract
    @param _nullifierHash The hash of unique deposit nullifier to prevent double spends
    @param _recipient The recipient address
    @param _repaymentAmount  the amount of stablecoin that a user is repaying to redeem their collateral for.
     */
    function withdraw(
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c,
        bytes32 _root,
        bytes32 _nullifierHash,
        address payable _recipient,
        uint256 _repaymentAmount
    ) external;
    
    /**
    @notice Returns The details of a vault
    @param _nullifierHash The hash of unique deposit nullifier to prevent double spends
    @return vault The vault details
     */
    function getVaultDetails(bytes32 _nullifierHash) external view returns(VaultDetails memory vault);
    
    /**
    @notice Returns an estimate of how much collateral could be withdrawn for a given amount of stablecoin
    @param repaymentAmount  the amount of stable coin that would be repaid
    @return collateralAmount the estimated amount of a vault's collateral that would be returned 
     */
    function estimateCollateralAmount(uint256 repaymentAmount) external view returns(uint256 collateralAmount);
    
    /**
    @notice Returns an estimate on how much stable coin could be minted at the current rate
    @param depositAmount the amount of ETH that would be deposited
    @return tokenAmount  the estimated amount of stablecoin that would be minted
     */
    function estimateTokenAmount(uint256 depositAmount) external view returns(uint256 tokenAmount);
}