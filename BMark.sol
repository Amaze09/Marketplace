// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./erc721.sol";
import "./erc1155.sol";

contract Marketplace is Ownable, ReentrancyGuard, IERC721Receiver {
    using Counters for Counters.Counter;                                      

    Counters.Counter private _listingIds1155;

    Counters.Counter private _itemIds721;
    Counters.Counter private _itemsSold721;
    Counters.Counter private _itemsCancelled721;


    uint256 public platformFees = 2000000000000000;                                                 
    uint8 public commission = 4 ;
    
    
    Listing1155[] private listingsArray1155;


    address private erc721;

    address private erc1155;

    mapping(uint256 => Listing1155) private idToListing1155;

    mapping(address => mapping(uint256 => tokenDetails721)) public tokenToAuction721;

    mapping(address => mapping(uint256 => mapping(address => uint256))) public bids721;

    mapping(uint256 => MarketItem721) private idToMarketItem721;

    BharatERC721 private BERC721;   
    BharatERC1155 private BERC1155;   

     enum MarketItemStatus721 {
        Active,
        Sold,
        Cancelled
    }                                         

    constructor(address _erc721, address _erc1155) {
    
        BERC721 = BharatERC721(_erc721);
        BERC1155 = BharatERC1155(_erc1155);
    }

    struct tokenDetails721 {
        address seller;
        uint128 price;
        uint256 duration;
        uint256 maxBid;
        address maxBidUser;
        bool isActive;
        uint256[] bidAmounts;
        address[] users;
    }

    struct MarketItem721 {
        uint256 itemId;
        uint256 tokenId;
        address payable seller;
        address payable owner;
        uint256 price;
        MarketItemStatus721 status;
    }

    struct Listing1155 {
        address seller;
        address[] buyer;
        uint256 tokenId;
        uint256 amount;
        uint256 price;
        uint256 tokensAvailable;
        bool privateListing;
        bool completed;
        uint listingId;
    }

    event TokenListed1155(                                                         
        address indexed seller, 
        uint256 indexed tokenId, 
        uint256 amount, 
        uint256 pricePerToken, 
        address[] privateBuyer, 
        bool privateSale, 
        uint indexed listingId
    );

    event TokenSold1155(
        address seller, 
        address buyer, 
        uint256 tokenId, 
        uint256 amount, 
        uint256 pricePerToken, 
        bool privateSale
    );

    event ListingDeleted1155(
        uint indexed listingId
    );



     function getRoyalties721(uint256 tokenId, uint256 price)
        private
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        (receiver, royaltyAmount) = BERC721.royaltyInfo(tokenId, price);
        if (receiver == address(0) || royaltyAmount == 0) {
            return (address(0), 0);
        }
        return (receiver, royaltyAmount);
    }


    function getRoyalties1155(uint256 tokenId, uint256 price)
        private
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        (receiver, royaltyAmount) = BERC1155.royaltyInfo(tokenId, price);
        if (receiver == address(0) || royaltyAmount == 0) {
            return (address(0), 0);
        }
        return (receiver, royaltyAmount);
    }



//-----------------------------------------------------------------------------ERC721--------------------------------------------------------------------------------//


    function createMarketItem(uint256 tokenId, uint256 price)
        external
        payable
    {
        require(
            BERC721.ownerOf(tokenId) == msg.sender,
            "Sender does not own the item"
        );
        require(price > 0, "Price must be at least 1 wei");
        require(
            msg.value >= platformFees,
            "Price must be equal to listing price"
        );
         require(
            BERC721.getApproved(tokenId) == address(this),
            "Market is not approved"
        );
        BERC721.transferFrom(msg.sender, address(this), tokenId);

        _itemIds721.increment();

        uint256 itemId = _itemIds721.current();

        idToMarketItem721[itemId] = MarketItem721(
            itemId,
            tokenId,
            payable(msg.sender),
            payable(address(0)),
            price,
            MarketItemStatus721.Active
        );

    }

     function createMarketSale721(uint256 itemId)
        external
        payable
        nonReentrant
    {
        require(itemId <= _itemIds721.current() && itemId > 0, "Could not find item");
        MarketItem721 storage idToMarketItem_ = idToMarketItem721[itemId];
        uint256 tokenId = idToMarketItem_.tokenId;
        require(
            idToMarketItem_.status == MarketItemStatus721.Active,
            "Listing Not Active"
        );
        require(msg.sender != idToMarketItem_.seller, "Seller can't be buyer");
        require(
            msg.value == idToMarketItem_.price,
            "Please submit the asking price in order to complete the purchase"
        );

        (address royaltyReceiver, uint256 royaltyAmount) = getRoyalties721(
            tokenId,
            msg.value
        );

        (bool success, ) = idToMarketItem_.seller.call{value: ((idToMarketItem_.price - royaltyAmount)*(100 - commission))/100}("");
            require(success);

        (bool success0, ) = royaltyReceiver.call{value: royaltyAmount}("");
            require(success0);    
        
        BERC721.transferFrom(address(this), msg.sender, tokenId);
        
        idToMarketItem_.owner = payable(msg.sender);
        idToMarketItem_.status = MarketItemStatus721.Sold;
        _itemsSold721.increment();
      
    }

    function cancelMarketItem(uint256 itemId)
        external
        nonReentrant
    {
        require(itemId <= _itemIds721.current() && itemId > 0, "Could not find item");
        MarketItem721 storage idToMarketItem_ = idToMarketItem721[itemId];
        require(msg.sender == idToMarketItem_.seller, "Only Seller can Cancel");
        require(
            idToMarketItem_.status == MarketItemStatus721.Active,
            "Item must be active"
        );
        idToMarketItem_.status = MarketItemStatus721.Cancelled;
        _itemsCancelled721.increment();
        
        BERC721.transferFrom(address(this), msg.sender, idToMarketItem_.tokenId);

    }


function createTokenAuction721(
        uint256 _tokenId,
        uint128 _price,
        uint256 _duration
    ) external {
        require(msg.sender != address(0), "Invalid Address");
        require(msg.sender == BERC721.ownerOf(_tokenId), "Not the owner of tokenId");
        require(_price > 0, "Price should be more than 0");
        require(_duration > 0, "Invalid duration value");
        tokenDetails721 memory _auction = tokenDetails721({
            seller: msg.sender,
            price: uint128(_price),
            duration: _duration,
            maxBid: 0,
            maxBidUser: address(0),
            isActive: true,
            bidAmounts: new uint256[](0),
            users: new address[](0)
        });
        address owner = msg.sender;
        BERC721.safeTransferFrom(owner, address(this), _tokenId);
        tokenToAuction721[erc721][_tokenId] = _auction;
    }
    /**
       Users bid for a particular nft, the max bid is compared and set if the current bid id highest
    */
    function bid721(uint256 _tokenId) external payable {
        tokenDetails721 storage auction = tokenToAuction721[erc721][_tokenId];
        require(msg.value >= auction.price, "bid price is less than current price");
        require(auction.isActive, "auction not active");
        require(auction.duration > block.timestamp, "Deadline already passed");
        if (bids721[erc721][_tokenId][msg.sender] > 0) {
            (bool success, ) = msg.sender.call{value: bids721[erc721][_tokenId][msg.sender]}("");
            require(success);
        }
        bids721[erc721][_tokenId][msg.sender] = msg.value;
        if (auction.bidAmounts.length == 0) {
            auction.maxBid = msg.value;
            auction.maxBidUser = msg.sender;
        } else {
            uint256 lastIndex = auction.bidAmounts.length - 1;
            require(auction.bidAmounts[lastIndex] < msg.value, "Current max bid is higher than your bid");
            auction.maxBid = msg.value;
            auction.maxBidUser = msg.sender;
        }
        auction.users.push(msg.sender);
        auction.bidAmounts.push(msg.value);
    }
    /**
       Called by the seller when the auction duration is over the hightest bid user get's the nft and other bidders get eth back
    */
    function executeSale721(uint256 _tokenId) external {
        tokenDetails721 storage auction = tokenToAuction721[erc721][_tokenId];
        require(auction.duration <= block.timestamp, "Deadline did not pass yet");
        require(auction.seller == msg.sender, "Not seller");
        require(auction.isActive, "auction not active");
        auction.isActive = false;

        (address royaltyReceiver, uint256 royaltyAmount) = getRoyalties721(
            _tokenId,
            auction.maxBid
        );

        if (auction.bidAmounts.length == 0) {
            ERC721(BERC721).safeTransferFrom(
                address(this),
                auction.seller,
                _tokenId
            );
        } else {

            (bool success, ) = auction.seller.call{value: ((auction.maxBid - royaltyAmount)*(100 - commission))/100}("");
            require(success);

            (bool success0, ) = royaltyReceiver.call{value: royaltyAmount}("");
            require(success0);


            for (uint256 i = 0; i < auction.users.length; i++) {
                if (auction.users[i] != auction.maxBidUser) {
                    (success, ) = auction.users[i].call{
                        value: bids721[erc721][_tokenId][auction.users[i]]
                    }("");
                    require(success);
                }
            }
            BERC721.safeTransferFrom(
                address(this),
                auction.maxBidUser,
                _tokenId
            );
        }
    }

    /**
       Called by the seller if they want to cancel the auction for their nft so the bidders get back the locked eeth and the seller get's back the nft
    */

    function cancelAuction721(uint256 _tokenId) external {
        tokenDetails721 storage auction = tokenToAuction721[erc721][_tokenId];
        require(auction.seller == msg.sender, "Not seller");
        require(auction.isActive, "auction not active");
        auction.isActive = false;
        bool success;
        for (uint256 i = 0; i < auction.users.length; i++) {
        (success, ) = auction.users[i].call{value: bids721[erc721][_tokenId][auction.users[i]]}("");        
        require(success);
        }
        BERC721.safeTransferFrom(address(this), auction.seller, _tokenId);
    }

    function getTokenAuctionDetails721(uint256 _tokenId) public view returns (tokenDetails721 memory) {
        tokenDetails721 memory auction = tokenToAuction721[erc721][_tokenId];
        return auction;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    )external override pure returns(bytes4) {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }

    receive() external payable {}



//-----------------------------------------------------------------------------ERC1155--------------------------------------------------------------------------------//



    
     function listToken1155(uint256 tokenId, uint256 amount, uint256 price, address[] memory privateBuyer) public payable nonReentrant returns(uint256) {
        require(msg.value >= platformFees, "platform fees required for listing");
        require(amount > 0, "Amount must be greater than 0!");
        require(BERC1155.balanceOf(msg.sender, tokenId) >= amount, "Caller must own given token!");
        require(BERC1155.isApprovedForAll(msg.sender, address(this)), "Contract must be approved!");

        bool privateListing = privateBuyer.length>0;
        _listingIds1155.increment();
        uint256 listingId = _listingIds1155.current();
        idToListing1155[listingId] = Listing1155(msg.sender, privateBuyer, tokenId, amount, price, amount, privateListing, false, _listingIds1155.current());
        listingsArray1155.push(idToListing1155[listingId]);

        emit TokenListed1155(msg.sender, tokenId, amount, price, privateBuyer, privateListing, _listingIds1155.current());

        return _listingIds1155.current();
    }

    function purchaseToken1155(uint256 listingId, uint256 amount) public payable nonReentrant {
        
        if(idToListing1155[listingId].privateListing == true) {
            bool whitelisted = false;
            for(uint i=0; i<idToListing1155[listingId].buyer.length; i++){
                if(idToListing1155[listingId].buyer[i] == msg.sender) {
                    whitelisted = true;
                }
            }
            require(whitelisted == true, "Sale is private!");
        }

        require(msg.sender != idToListing1155[listingId].seller, "Can't buy your own tokens!");
        require(msg.value >= idToListing1155[listingId].price * amount, "Insufficient funds!");
        require(BERC1155.balanceOf(idToListing1155[listingId].seller, idToListing1155[listingId].tokenId) >= amount, "Seller doesn't have enough tokens!");
        require(idToListing1155[listingId].completed == false, "Listing not available anymore!");
        require(idToListing1155[listingId].tokensAvailable >= amount, "Not enough tokens left!");

        idToListing1155[listingId].tokensAvailable -= amount;
        listingsArray1155[listingId-1].tokensAvailable -= amount;
        if(idToListing1155[listingId].privateListing == false){
            idToListing1155[listingId].buyer.push(msg.sender);
            listingsArray1155[listingId-1].buyer.push(msg.sender);
        }
        if(idToListing1155[listingId].tokensAvailable == 0) {
            idToListing1155[listingId].completed = true;
            listingsArray1155[listingId-1].completed = true;
        }

        emit TokenSold1155(
            idToListing1155[listingId].seller,
            msg.sender,
            idToListing1155[listingId].tokenId,
            amount,
            idToListing1155[listingId].price,
            idToListing1155[listingId].privateListing
        );

        (address royaltyReceiver, uint256 royaltyAmount) = getRoyalties1155(
            idToListing1155[listingId].tokenId,
            idToListing1155[listingId].price
        );

        BERC1155.safeTransferFrom(idToListing1155[listingId].seller, msg.sender, idToListing1155[listingId].tokenId, amount, "");


        (bool success, ) = idToListing1155[listingId].seller.call{value: ((idToListing1155[listingId].price - royaltyAmount*amount)*(100 - commission))/100}("");
            require(success);

        (bool success0, ) = royaltyReceiver.call{value: royaltyAmount*amount}("");
            require(success0);    


    }

    function deleteListing1155(uint _listingId) public {
        require(msg.sender == idToListing1155[_listingId].seller, "Not caller's listing!");
        require(idToListing1155[_listingId].completed == false, "Listing not available!");
        
        idToListing1155[_listingId].completed = true;
        listingsArray1155[_listingId-1].completed = true;

        emit ListingDeleted1155(_listingId);
    }

    function  viewAllListings1155() public view returns (Listing1155[] memory) {
        return listingsArray1155;
    }

    function viewListingById1155(uint256 _id) public view returns(Listing1155 memory) {
        return idToListing1155[_id];
    }

//------------------------------------------------------------------------------------------------------------------------------------------------------------------------------//

    function withdrawAll() public payable onlyOwner {
	(bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
		require(success);
	}


}