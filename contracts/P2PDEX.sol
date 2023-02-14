// SPDX-License-Identifier: UNLICENSED

/*
    This software is currently UNLICENSED, which means you may not copy the code and we (Rohit Kumar Gupta, and TurbineSwap) 
    are the sole copyright owners. We may change the license after release, so stay tuned.
*/

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./SellerVault.sol";

contract P2PDEX is Ownable {
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
    //Struct to hold information about a buy order
    struct BuyOrder {
        address buyer;
        uint256 orderId;
        uint256 amount;
        uint256 state; // 1 for placed, 2 for paid, 3 for settled, 4 for cancelled
        uint256 timeStamp;
    }
    using Counters for Counters.Counter;
    Counters.Counter private _listings;
    Counters.Counter private _activeListings;
    Counters.Counter private _buyOrderId;
    uint256 private _maxTimeAllowedToCancelBuy; 
    uint256 private _fee;
    address payable private _feeTo;
    uint256 private _tax;
    address payable private _taxTo;
    address[] private _arbitrators;
    //_paymentMethodId is a counter for the number of payment methods. 
    Counters.Counter private _paymentMethodId;
    //_paymentMethods is a mapping that maps the payment method id to the name of payment method.
    mapping(uint256 => string) private _paymentMethods;
    // Mapping to hold vaults of a seller. Only one vault per seller.
    mapping(address => address) public vault;
    //Mapping to hold all the listings
    mapping(uint256 => Listing) public listings;
    //<apping to hold listing id per address
    mapping(address => uint256[]) private _listingsPerSeller;
    //Mapping to hold Buy Order Info
    mapping(uint256 => BuyOrder) public buyOrders;
    //Mapping to hold all Buy Orders of a Buyer
    mapping(address => uint256[]) private _buysPerSeller;
    //Mapping for buy order id to listing ID
    mapping(uint256 => uint256) public buyOrderListingId;
    //Mapping for blocked buy amount
    mapping(address => uint256) private _blockedBuyAmount;
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
        require(amount <= (vault[msg.sender].balance - SellerVault(vault[msg.sender]).blockedAmount()), "Insufficient balance, please fund the wallet first.");
        SellerVault(vault[msg.sender]).addBlockEth(amount);
        //Check if the seller already has a listing for the given token
        _listings.increment();
        _activeListings.increment();
        //Create a new listing
        listings[_listings.current()] = Listing(msg.sender, _listings.current(), price, currency, amount, 1);
        _listingsPerSeller[msg.sender].push(_listings.current());
        //Emit event for a new listing
        emit NewListing(_listings.current(), msg.sender, price, currency, amount);
    }

    function modifyListing(uint256 listingId, uint256 newPrice) external {
        require(listings[listingId].seller == msg.sender, "Only the seller can close thier listing.");
        //Add a require statement to check for active buy orders revert if there is an active buy order. 
        //Essentially check for block amounts.
        require(_blockedBuyAmount[msg.sender] == 0, "Active buy orders. Can't change price now.");
        listings[listingId].price = newPrice;
    }

    function closeListing(uint256 listingId) external {
        require(listings[listingId].seller == msg.sender, "Only the seller can close thier listing.");
        require(listings[listingId].state == 1, "Listing already closed or has active buy Order. Please try again later.");
        SellerVault(vault[msg.sender]).reduceBlockEth(listings[listingId].amount);
        listings[listingId].amount = 0;
        listings[listingId].state = 3;
        _activeListings.decrement();
        emit CloseListing(listingId);
    }

    function placeBuyOrder(uint256 listingId, uint256 amount) external {
        require(listings[listingId].state == 1 || listings[listingId].state == 2, "Listing inactive.");
        require((listings[listingId].amount - _blockedBuyAmount[listings[listingId].seller]) >= amount, "Please retry with amount less than or equal to the listing.");
        listings[listingId].state = 2;
        increaseBlockAmount(listings[listingId].seller, amount);
        _buyOrderId.increment();
        buyOrders[_buyOrderId.current()] = BuyOrder(msg.sender, _buyOrderId.current(), amount, 1, block.timestamp);
        buyOrderListingId[_buyOrderId.current()] = listingId;
    }

    function markPaid(uint256 buyOrderId) external {
        require(buyOrders[buyOrderId].buyer == msg.sender, "Only the buyer can execute this function.");
        buyOrders[buyOrderId].state = 2;
    }

    function releaseTokens(uint256 buyOrderId) external {
        require(listings[buyOrderListingId[buyOrderId]].seller == msg.sender, "Only the seller can call this function.");
        require(buyOrders[buyOrderId].state != 3, "Already Paid.");
        require(buyOrders[buyOrderId].state != 4, "Buy order cancelled.");
        buyOrders[buyOrderId].state = 3;
        listings[buyOrderListingId[buyOrderId]].amount -= buyOrders[buyOrderId].amount;
        SellerVault(vault[msg.sender]).reduceBlockEth(buyOrders[buyOrderId].amount);
        SellerVault(vault[msg.sender]).settleBuyOrder(payable(buyOrders[buyOrderId].buyer), buyOrders[buyOrderId].amount);
        decreaseBlockAmount(listings[buyOrderListingId[buyOrderId]].seller, buyOrders[buyOrderId].amount);
        if (listings[buyOrderListingId[buyOrderId]].amount == 0) {
            listings[buyOrderListingId[buyOrderId]].state = 3;
            _activeListings.decrement();
            emit CloseListing(buyOrderListingId[buyOrderId]);
        } else if (_blockedBuyAmount[listings[buyOrderListingId[buyOrderId]].seller] == 0) {
            listings[buyOrderListingId[buyOrderId]].state = 1;
        }
    }

    // Other settings start here..

    function setMaxBuyTime(uint256 time) external onlyOwner {
            _maxTimeAllowedToCancelBuy = time;
    }

    function setFeeDetails(uint256 fee, address payable feeTo) external onlyOwner {
        _fee = fee;
        _feeTo = feeTo;
    }

    function setTaxDetails(uint256 tax, address payable taxTo) external onlyOwner {
        _tax = tax;
        _taxTo = taxTo;
    }

    function addArbitrator(address arbitrator) external onlyOwner {
        _arbitrators.push(arbitrator);
    }

    function removeArbitrator(uint256 index) external onlyOwner {
        require(index < _arbitrators.length, "Index out of bounds");
        address[] memory newArbitrators = new address[](_arbitrators.length - 1);
        uint256 newIndex = 0;
        for (uint256 i = 0; i < _arbitrators.length; i++) {
            if (i != index) {
                newArbitrators[newIndex] = _arbitrators[i];
                newIndex++;
            }
        }
        delete _arbitrators;
        _arbitrators = newArbitrators;
    }

    function addPaymentMethods(uint256 numberOfMethods, string[] memory methods) external onlyOwner {
        require(numberOfMethods > 0, "Methods should be at least one.");
        require(methods.length == numberOfMethods, "Method numbers mismatch.");
        for (uint256 i = 0; i < numberOfMethods; i++) {
            _paymentMethodId.increment();
            _paymentMethods[_paymentMethodId.current()] = methods[i];
        }
    }

    function increaseBlockAmount(address seller, uint256 amount) internal {
        _blockedBuyAmount[seller] += amount;
    }

    function decreaseBlockAmount(address seller, uint256 amount) internal {
        require(amount <= _blockedBuyAmount[seller], "Cannot Unblock more amount than already blocked.");
        _blockedBuyAmount[seller] -= amount;
    }

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

    function getMaxBuyTime() public view returns (uint256) {
        return _maxTimeAllowedToCancelBuy;
    }

    function getBlockAmountBySeller() external view returns (uint256) {
        return _blockedBuyAmount[msg.sender];
    }

    function getFee() external view returns (uint256) {
        return _fee;
    }

    function getFeeTo() external view returns (address payable) {
        return _feeTo;
    }

    function getTax() external view returns (uint256) {
        return _tax;
    }

    function getTaxTo() external view returns (address payable) {
        return _taxTo;
    }

    function getListingsBySeller() external view returns (uint256[] memory) {
        return _listingsPerSeller[msg.sender];
    }

    function getArbitrators() external view returns (address[] memory) {
        return _arbitrators;
    }

    function getPaymentMethods() external view returns (string[] memory) {
        string[] memory paymentMethodsList = new string[](_paymentMethodId.current());
        for(uint256 i = 0; i < _paymentMethodId.current(); i++) {
            paymentMethodsList[i] = _paymentMethods[i+1];
        }
        return paymentMethodsList;
    }

    function getPaymentMethod(uint256 index) external view returns (string memory) {
        return _paymentMethods[index];
    }

    function getPaymentMethodsCount() external view returns (uint256) {
        return _paymentMethodId.current();
    }
}
