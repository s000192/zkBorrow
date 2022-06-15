// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./interfaces/IVault.sol";
import "./MerkleTreeWithHistory.sol";
import "./ZkUsd.sol";
import "./PriceConsumerV3.sol";
import "./Verifier.sol";
import "./mock/MockOracle.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Vault is IVault, MerkleTreeWithHistory, Verifier, Ownable, ReentrancyGuard {
    ZkUsd public token;
    PriceConsumerV3 private oracle;

    mapping(bytes32 => VaultDetails) public nullifierHashes;
    mapping(bytes32 => bool) public commitments;

    uint256 public defaultDeposit;
    uint256 public collateralisationRatio;

    constructor(
        IHasher _hasher,
        ZkUsd _token,
        PriceConsumerV3 _oracle,
        uint256 _defaultDeposit,
        uint256 _collateralisationRatio,
        uint32 _merkleTreeHeight
    ) MerkleTreeWithHistory(_merkleTreeHeight, _hasher) {
        require(_defaultDeposit > 0, "default deposits should be greater than 0");
        token = _token;
        oracle = _oracle;
        defaultDeposit = _defaultDeposit;
        collateralisationRatio = _collateralisationRatio;
    }

    /**
    @notice Allows a user to deposit ETH collateral in exchange for some amount of stablecoin
    @param _commitment The note commitment, which is PedersenHash(nullifier + secret)
     */
    function deposit(bytes32 _commitment) override payable external {
        require(!commitments[_commitment], "The commitment has been submitted");
        require(defaultDeposit == msg.value, "incorrect ETH amount");

        uint32 insertedIndex = _insert(_commitment);
        commitments[_commitment] = true;

        emit Deposit(_commitment, insertedIndex, block.timestamp);
    }

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
    ) override external nonReentrant {
        require(isKnownRoot(_root), "Cannot find your merkle root");
        require(
            verifyProof(
              a,
              b,
              c,
              [uint256(_root), uint256(_nullifierHash)]
            ),
            "Invalid proof"
        );
        
        // check amount to mint is below collateral ratio
        require(getMaxBorrowAmount(_nullifierHash) >= _borrowAmount, "Collateral not enough");
        // accounting
        if (!nullifierHashes[_nullifierHash].initialised) {
            nullifierHashes[_nullifierHash].initialised = true;
            nullifierHashes[_nullifierHash].collateralAmount = defaultDeposit;
        }
        nullifierHashes[_nullifierHash].debtAmount += _borrowAmount;
        // mint
        token.mint(_recipient, _borrowAmount);

        emit Borrow(_recipient, _nullifierHash, _borrowAmount);
    }
    
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
    ) override external nonReentrant {
        require(isKnownRoot(_root), "Cannot find your merkle root");
        require(
            verifyProof(
              a,
              b,
              c,
              [uint256(_root), uint256(_nullifierHash)]
            ),
            "Invalid proof"
        );

        require(_repaymentAmount <= nullifierHashes[_nullifierHash].debtAmount, "withdraw limit exceeded"); 
        require(token.balanceOf(msg.sender) >= _repaymentAmount, "not enough tokens in balance");
        uint256 amountToWithdraw = _repaymentAmount / getEthUSDPrice() * 100 / collateralisationRatio;
        token.burn(msg.sender, _repaymentAmount);
        nullifierHashes[_nullifierHash].collateralAmount -= amountToWithdraw;
        nullifierHashes[_nullifierHash].debtAmount -= _repaymentAmount;
        (bool success, ) = _recipient.call{ value: amountToWithdraw }("");
        require(success, "payment to _recipient did not go thru");
        emit Withdrawal(_recipient, _nullifierHash, amountToWithdraw, _repaymentAmount);
    }

    
    /**
    @notice Returns the details of a vault
    @param _nullifierHash The hash of unique deposit nullifier to prevent double spends
    @return vault  the vault details
     */
    function getVaultDetails(bytes32 _nullifierHash) external view override returns(VaultDetails memory vault) {
        return nullifierHashes[_nullifierHash];
    }
    
    /**
    @notice Returns an estimate of how much collateral could be withdrawn for a given amount of stablecoin
    @param repaymentAmount  the amount of stable coin that would be repaid
    @return collateralAmount the estimated amount of a vault's collateral that would be returned 
     */
    function estimateCollateralAmount(uint256 repaymentAmount) external view override  returns(uint256 collateralAmount) {
        return repaymentAmount / getEthUSDPrice();
    }
    
    /**
    @notice Returns an estimate on how much stable coin could be minted at the current rate
    @param depositAmount the amount of ETH that would be deposited
    @return tokenAmount  the estimated amount of stablecoin that would be minted
     */
    function estimateTokenAmount(uint256 depositAmount) external view override returns(uint256 tokenAmount) {
        return depositAmount * getEthUSDPrice();
    }

    /**
    @notice Returns an estimate on how much stable coin could be minted at the current rate
    @param _nullifierHash The hash of unique deposit nullifier to prevent double spends
    @return tokenAmount  the estimated amount of stablecoin that would be minted
     */
    function getMaxBorrowAmount(bytes32 _nullifierHash) public view returns(uint256 tokenAmount) {
        return (defaultDeposit * getEthUSDPrice() - nullifierHashes[_nullifierHash].debtAmount) * collateralisationRatio / 100;
    }

    function getEthUSDPrice() public view returns (uint256){
        uint price8 = uint(oracle.getLatestPrice());
        return price8*(10**10);
    }

    function getToken() external view returns (address){
        return address(token);
    }

    function setOracle(address _oracle) public onlyOwner {
        oracle = PriceConsumerV3(_oracle);
    }

    function setCollateralisationRatio(uint256 _ratio) public onlyOwner {
        collateralisationRatio = _ratio;
    }

    function getOracle() public view returns (address) {
        return address(oracle);
    }
}
