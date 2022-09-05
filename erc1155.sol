// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./ERC2981Royalties.sol";

contract BERC1155 is ERC1155, Ownable, ERC2981Royalties {
    using Strings for uint256;
    
    uint256 private _tokenIds;
    uint256 private constant supply = 9999999999999999999;
    string[supply] private _tokenUris;
    constructor() ERC1155("") {}
    
    function addTokenUri(uint256 tokenId, string memory tokenUri) internal {
        _tokenUris[tokenId] = tokenUri;
    }
    
    function uri(uint256 _id) public view override returns (string memory) {
        if (bytes(_tokenUris[_id]).length > 0) {
            return _tokenUris[_id];
        }
      
        return string(super.uri(_id));
    }
    
    function mint(uint256 _numNfts, string memory _uri, address royaltyRecipient,
        uint256 royaltyPercent)
        external
    {
        require(_tokenIds <= supply, "The End");
        addTokenUri(_tokenIds, _uri);
        _mint(msg.sender, _tokenIds, _numNfts, "");
        if (royaltyPercent > 0) {
            _setTokenRoyalty(_tokenIds, royaltyRecipient, royaltyPercent);
        }
        _tokenIds += 1;
        
    }
    
}
