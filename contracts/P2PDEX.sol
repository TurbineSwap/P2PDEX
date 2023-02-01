// SPDX-License-Identifier: UNLICENSED

/*
    This software is currently UNLICENSED, which means you may not copy the code and we (Rohit Kumar Gupta, and TurbineSwap) 
    are the sole copyright owners. We may change the license after release, so stay tuned.
*/

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/Counters.sol";
import "./SellerVault.sol";

contract P2PDEX {
    //Struct to hold information about a listing
    struct Listing {
        address seller;
        uint256 listingId;
        uint256 price;
        uint256 currency; // 1 for Native, 2 for DAI, 3 for USDC, 4 for USDT
        uint256 amount;
        //uint256[] paymentMethods; 
        uint256 state; // 1 for active, 2 for pending orders, 3 for inactive
    }
    using Counters for Counters.Counter;
    Counters.Counter private _listings;
    Counters.Counter private _activeListings;
    // Mapping to hold vaults of a seller. Only one vault per seller.
    mapping(address => address) public vault;
    //Mapping to hold all the listings
    mapping(uint256 => Listing) public listings;
    //Event for a new Vault
    event NewVault(address indexed sellerAddress, address indexed vaultAddress);
    //Event for a new funding
    event NewFunding(address indexed vaultAddress, uint256 amount);
    //Event for a new listing
    event NewListing(uint256 indexed listingId, address indexed seller, uint256 price, uint256 currency, uint256 amount);
    //Event for update an existing listing
    event UpdateListing(uint256 indexed listingId, uint256 indexed newPrice);
    //Event for closing an existing listing
    event CloseListing(uint256 indexed listingId);
    //Event for a new order
    event NewOrder(address indexed buyer, uint256 indexed listingId, uint256 price);
    //Event for an order being settled
    event OrderSettled(address indexed buyer, uint256 indexed listingId);
    //Event for an order being cancelled
    event OrderCancelled(address indexed buyer, uint256 indexed listingId);

    modifier vaultGuard() {
        require(vault[msg.sender] == address(0), "Vault already exists for Seller.");
        _;
    }

    modifier payOrFail() {
        require(msg.value > 0, "Send some Ether.");
        _;
    }

    function createVault() internal returns (address) {
        SellerVault sellerVault = new SellerVault(payable(msg.sender));
        vault[msg.sender] = address(sellerVault);
        emit NewVault(msg.sender, address(sellerVault));
        return address(sellerVault);
    }

    function fundVault() internal returns (uint256) {
        SellerVault(vault[msg.sender]).deposit{value: msg.value}();
        emit NewFunding(vault[msg.sender], msg.value);
        return(msg.value);
    }

    function createAndFundVault() external payable vaultGuard payOrFail {
        createVault();
        fundVault();
    }

    function onlyCreateVault() external vaultGuard {
        createVault();
    }

    function onlyFundVault() external payable payOrFail {
        require(vault[msg.sender] != address(0), "Create Vault first.");
        fundVault();
    }
    
    //function to create a new listing
    function createListing(uint256 price, uint256 currency, uint256 amount) external {
        require(vault[msg.sender] != address(0), "Vault doesn't exist for seller. Please Create Vault first.");
        require(amount <= (vault[msg.sender].balance + SellerVault(vault[msg.sender]).blockedAmount()), "Insufficient balance, please fund the wallet first.");
        SellerVault(vault[msg.sender]).addBlockEth(amount);
        //Check if the seller already has a listing for the given token
        _listings.increment();
        _activeListings.increment();
        //Create a new listing
        listings[_listings.current()] = Listing(msg.sender, _listings.current(), price, currency, 1, amount);
        //Emit event for a new listing
        emit NewListing(_listings.current(), msg.sender, price, currency, amount);
    }

    function closeListing(uint256 listingId) external {
        require(listings[listingId].seller == msg.sender, "Only the seller can close thier listing.");
        require(listings[listingId].state == 1 || listings[listingId].state == 2, "Listing already closed");
        listings[listingId].state = 3;
        _activeListings.decrement();
        emit CloseListing(listingId);
    }

    /*
    //function to update the price of a listing
    function updatePrice(uint256 listingId, uint256 newPrice) public {
        //Check if the listing is active
        require(listings[listingId].state == 1);
        //Check if the msg.sender is the seller of the listing
        require(listings[listingId].seller == msg.sender);
        //Update the price of the listing
        listings[listingId].price = newPrice;
    }
    //function to place a buy order
    function placeOrder(uint256 listingId) public {
        //Check if the listing is active
        require(listings[listingId].state == 1);
        //Check if the buyer already has a pending order
        require(listings[listingId].state != 2);
        //Update the state of the listing to pending
        listings[listingId].state = 2;
        //Emit event for a new order
        emit NewOrder(msg.sender, listingId, listings[listingId].price);
    }
    //function to settle an order
    function settleOrder(uint256 listingId) public {
        //Check if the listing is in pending state
        require(listings[listingId].state == 2);
        //Check if the msg.sender is the seller of the listing
        require(listings[listingId].seller == msg.sender);
        //Transfer the tokens to the buyer
        //transferFrom(...)
        //Transfer the funds to the seller
        //transfer(...)
        //Update the state of the listing to inactive
        listings[listingId].state = 3;
        //Emit event for an order being settled
        emit OrderSettled(msg.sender, listingId);
    }
    //function to cancel an order
    function cancelOrder(uint256 listingId) public {
        //Check if the listing is in pending state
        require(listings[listingId].state == 2);
        //Check if the msg.sender is the buyer of the listing
        require(listings[msg.sender].listingId == listingId);
        //Update the state of the listing to active
        listings[listingId].state = 1;
        //Emit event for an order being cancelled
        emit OrderCancelled(msg.sender, listingId);
    }
    */

   //Function to view Listings that are active. All other view only functions start from here...
    function getActiveListings() public view returns (Listing[] memory) {
        Listing[] memory activeListings = new Listing[](_activeListings.current());
        uint256 activeListingCount = 0;
        for (uint256 i = 0; i <= _listings.current(); i++) {
            Listing storage listing = listings[i];
            if (listing.state == 1 || listing.state == 2) {
                activeListings[activeListingCount] = listing;
                activeListingCount++;
            }
        }
        return activeListings;
    }

}
