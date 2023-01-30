// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SellerVault is Ownable, ReentrancyGuard {
    address payable private _seller;
    uint256 public blockedAmount;
    uint256 public blockedDAI;
    uint256 public blockedUSDC;
    uint256 public blockedUSDT;

    // Stables Address on Arbitrum. Change for other chains.
    address payable public DAI = payable(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
    address payable public USDC = payable(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address payable public USDT = payable(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);

    constructor(address payable seller) {
        _seller = seller;
        blockedAmount = 0;
        blockedDAI = 0;
        blockedUSDC = 0;
        blockedUSDT = 0;
    }

    function getSeller() external view returns (address) {
        return _seller;
    }

    function deposit() external payable onlyOwner {
        // Deposit is processed but nothing happens unless user creates listing.
    }

    function depositDAI(uint256 amount) external onlyOwner {
        IERC20(DAI).transferFrom(_seller, address(this), amount);
    }

    function depositUSDC(uint256 amount) external onlyOwner {
        IERC20(USDC).transferFrom(_seller, address(this), amount);
    }

    function depositUSDT(uint256 amount) external onlyOwner {
        IERC20(USDT).transferFrom(_seller, address(this), amount);
    }

    function withdraw() external onlyOwner {
        uint256 withdrawableBal = address(this).balance - blockedAmount;
        require(withdrawableBal > 0, "Balance is either 0 or whole amount is blocked for trade.");
        _seller.transfer(withdrawableBal);
    }

    function withdrawDAI() external onlyOwner {
        uint256 withdrawableBal = IERC20(DAI).balanceOf(address(this)) - blockedDAI;
        require(withdrawableBal > 0, "Balance is either 0 or whole amount is blocked for trade.");
        IERC20(DAI).transfer(_seller, withdrawableBal);
    }

    function withdrawUSDC() external onlyOwner {
        uint256 withdrawableBal = IERC20(USDC).balanceOf(address(this)) - blockedUSDC;
        require(withdrawableBal > 0, "Balance is either 0 or whole amount is blocked for trade.");
        IERC20(USDC).transfer(_seller, withdrawableBal);
    }

    function withdrawUSDT() external onlyOwner {
        uint256 withdrawableBal = IERC20(USDT).balanceOf(address(this)) - blockedUSDT;
        require(withdrawableBal > 0, "Balance is either 0 or whole amount is blocked for trade.");
        IERC20(USDT).transfer(_seller, withdrawableBal);
    }

    // Blocks are added for any amount that is active in a Listing. This can't be withdrawn without first 
    // cancelling the listing.
    function addBlockEth(uint256 amount) external onlyOwner {
        require((address(this).balance >= (blockedAmount + amount)), "Cannot block more amount than Balance.");
        blockedAmount += amount;
    }

    function addBlockDai(uint256 amount) external onlyOwner {
        require((IERC20(DAI).balanceOf(address(this)) >= (blockedDAI + amount)), "Cannot block more amount than Balance.");
        blockedDAI += amount;
    }

    function addBlockUsdc(uint256 amount) external onlyOwner {
        require((IERC20(USDC).balanceOf(address(this)) >= (blockedUSDC + amount)), "Cannot block more amount than Balance.");
        blockedUSDC += amount;
    }

    function addBlockUsdt(uint256 amount) external onlyOwner {
        require((IERC20(USDT).balanceOf(address(this)) >= (blockedUSDT + amount)), "Cannot block more amount than Balance.");
        blockedUSDT += amount;
    }

    // Cancelling a listing automatically reduces the block and the funds can then be withdrawn, 
    function reduceBlockEth(uint256 amount) external onlyOwner {
        require(amount <= blockedAmount, "Cannot Unblock more amount than already blocked.");
        blockedAmount -= amount;
    }

    function reduceBlockDai(uint256 amount) external onlyOwner {
        require(amount <= blockedDAI, "Cannot Unblock more amount than already blocked.");
        blockedDAI -= amount;
    }

    function reduceBlockUsdc(uint256 amount) external onlyOwner {
        require(amount <= blockedUSDC, "Cannot Unblock more amount than already blocked.");
        blockedUSDC -= amount;
    }

    function reduceBlockUsdt(uint256 amount) external onlyOwner {
        require(amount <= blockedUSDT, "Cannot Unblock more amount than already blocked.");
        blockedUSDT -= amount;
    }
}