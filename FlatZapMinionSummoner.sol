// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.12;

interface IERC20ApproveTransfer { // interface for erc20 approve/transfer
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

library SafeMath { // arithmetic wrapper for unit under/overflow check
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b);
        return c;
    }
    
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0);
        uint256 c = a / b;
        return c;
    }
}


contract ReentrancyGuard { // call wrapper for reentrancy check
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() public {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}


abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () internal {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}


interface IMOLOCH { // brief interface for moloch dao v2


    function depositToken() external view returns (address);
    
    function tokenWhitelist(address token) external view returns (bool);
    
    function getProposalFlags(uint256 proposalId) external view returns (bool[6] memory);
    
    function members(address user) external view returns (address, uint256, uint256, bool, uint256, uint256);
    
    function userTokenBalances(address user, address token) external view returns (uint256);
    
    function cancelProposal(uint256 proposalId) external;

    function submitProposal(
        address applicant,
        uint256 sharesRequested,
        uint256 lootRequested,
        uint256 tributeOffered,
        address tributeToken,
        uint256 paymentRequested,
        address paymentToken,
        string calldata details
    ) external returns (uint256);
    
    function withdrawBalance(address token, uint256 amount) external;
}


contract ZapMinion is ReentrancyGuard {
    using SafeMath for uint256;
    
    IMOLOCH public moloch;
    
    address public manager; // account that manages moloch zap proposal settings (e.g., moloch via a minion)
    address public wrapper; // ether token wrapper contract reference for zap proposals
    uint256 public zapRate; // rate to convert ether into zap proposal share request (e.g., `10` = 10 shares per 1 ETH sent)
    uint256 public updateCount; 
    string public ZAP_DETAILS; // general zap proposal details to attach
    bool private initialized; // internally tracks deployment under eip-1167 proxy pattern

    mapping(uint256 => Zap) public zaps; // proposalId => Zap
    mapping(uint256 => Update) public updates;
    
    struct Zap {
        address proposer;
        bool processed;
        uint256 zapAmount;
       
    }
    
    struct Update {
        bool implemented;
        uint256 startBlock;
        uint256 newRate; 
        address manager;
        address wrapper;
        string newDetails;
    }

    event ProposeZap(uint256 amount, address indexed proposer, uint256 proposalId);
    event WithdrawZapProposal(address indexed proposer, uint256 proposalId);
    event UpdateZapMol(address indexed manager, address indexed wrapper, uint256 zapRate, string ZAP_DETAILS);
    event UpdateImplemented(bool implemented);

    function init(
        address _manager, 
        address _moloch, 
        address _wrapper, 
        uint256 _zapRate, 
        string memory _ZAP_DETAILS
    ) external {
        require(!initialized, "ZapMol::initialized");
        manager = _manager;
        moloch = IMOLOCH(_moloch);
        wrapper = _wrapper;
        zapRate = _zapRate;
        ZAP_DETAILS = _ZAP_DETAILS;
        IERC20ApproveTransfer(wrapper).approve(address(moloch), uint256(-1));
        initialized = true; 
    }
    
    receive() external payable nonReentrant { // caller submits share proposal to moloch per zap rate and msg.value
        (bool success, ) = wrapper.call{value: msg.value}("");
        require(success, "ZapMol::receive failed");
        require(msg.value % 10**18  == 0, "ZapMol::wrapper issue");
        require(msg.value >= zapRate && msg.value % zapRate  == 0, "ZapMol::no fractional shares");
        
        uint256 proposalId = moloch.submitProposal(
            msg.sender,
            0,
            msg.value.div(zapRate).div(10**18), // loot shares
            msg.value,
            wrapper,
            0,
            wrapper,
            ZAP_DETAILS
        );
        
        zaps[proposalId] = Zap(msg.sender, false, msg.value);

        emit ProposeZap(msg.value, msg.sender, proposalId);
    }
    
    
    
    function cancelZapProposal(uint256 proposalId) external nonReentrant { // zap proposer can cancel zap & withdraw proposal funds 
        Zap storage zap = zaps[proposalId];
        require(msg.sender == zap.proposer, "ZapMol::!proposer");
        require(!zap.processed, "ZapMol::already processed");
        bool[6] memory flags = moloch.getProposalFlags(proposalId);
        require(!flags[0], "ZapMol::already sponsored");
        
        uint256 zapAmount = zap.zapAmount;
        moloch.cancelProposal(proposalId); // cancel zap proposal in parent moloch
        moloch.withdrawBalance(wrapper, zapAmount); // withdraw zap funds from moloch
        zap.processed = true;

        IERC20ApproveTransfer(wrapper).transfer(msg.sender, zapAmount); // redirect funds to zap proposer
        
        emit WithdrawZapProposal(msg.sender, proposalId);
    }
    
    function drawZapProposal(uint256 proposalId) external nonReentrant { // if proposal fails, withdraw back to proposer
        Zap storage zap = zaps[proposalId];
        require(msg.sender == zap.proposer, "ZapMol::!proposer");
        require(!zap.processed, "ZapMol::already processed");
        bool[6] memory flags = moloch.getProposalFlags(proposalId);
        require(flags[1] && !flags[2], "ZapMol::proposal passed");
        
        uint256 zapAmount = zap.zapAmount;
        moloch.withdrawBalance(wrapper, zapAmount); // withdraw zap funds from parent moloch
        zap.processed = true;
                
        IERC20ApproveTransfer(wrapper).transfer(msg.sender, zapAmount); // redirect funds to zap proposer
        
        emit WithdrawZapProposal(msg.sender, proposalId);
    }
    
    function updateZapMol( // manager adjusts zap proposal settings
        address _manager, 
        address _wrapper, 
        uint256 _zapRate, 
        string calldata _ZAP_DETAILS
    ) external nonReentrant { 
        require(msg.sender == manager, "ZapMol::!manager");
        require(!updates[updateCount].implemented || updateCount == 0, "ZapMol::prior update !implemented");
        updateCount++;
        updates[updateCount] = Update(false, block.timestamp, _zapRate, _manager, _wrapper, _ZAP_DETAILS);
        
        emit UpdateZapMol(_manager, _wrapper, _zapRate, _ZAP_DETAILS);
    }
    
    function implmentUpdate(uint256 updateId) external nonReentrant returns (bool) {
        Update memory update = updates[updateId];
        require(!update.implemented, "ZapMol:: already implemented");
        require(updates[updateId-1].implemented, "ZapMol:: must implement prior update");
        require(block.timestamp > update.startBlock, "ZapMol:: must wait to implement");
    
        zapRate = update.newRate;
        manager = update.manager;
        wrapper = update.wrapper;
        ZAP_DETAILS = update.newDetails; 
        
     emit UpdateImplemented(true);
     return true;
  
    }  
}


/*
The MIT License (MIT)
Copyright (c) 2018 Murray Software, LLC.
Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:
The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
contract CloneFactory {
    function createClone(address payable target) internal returns (address payable result) { // eip-1167 proxy pattern adapted for payable minion
        bytes20 targetBytes = bytes20(target);
        assembly {
            let clone := mload(0x40)
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone, 0x14), targetBytes)
            mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            result := create(0, clone, 0x37)
        }
    }
}

// 0xd0A1E359811322d97991E03f863a0C30C2cF029C - wETH
// 0x7136fbDdD4DFfa2369A9283B6E90A040318011Ca - manager
// 0x901D2a2a7e8151EC4A27e607cEDB5B9930618128 - moloch 
// 1 - rate 

contract ZapMinionFactory is CloneFactory, Ownable {
    
    address payable immutable public template; // fixed template for minion using eip-1167 proxy pattern
    
    event SummonMinion(address indexed minion, address manager, address indexed moloch, uint256 zapRate, string name);
    
    constructor(address payable _template) public {
        template = _template;
    }
    
    // @DEV - zapRate should be entered in whole ETH or xDAI
    function summonZapMinion(address _manager, address _moloch, address _wrapper, uint256 _zapRate, string memory _ZAP_DETAILS) external returns (address) {
        
        string memory name = "Zap minion";
        ZapMinion zapminion = ZapMinion(createClone(template));
        zapminion.init(_manager, _moloch, _wrapper, _zapRate, _ZAP_DETAILS );
        
        emit SummonMinion(address(zapminion), _manager, _moloch, _zapRate, name);
        
        return(address(zapminion));
    }
    
}
