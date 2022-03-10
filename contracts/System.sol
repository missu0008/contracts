pragma solidity 0.6.4;

contract System {

  bool public alreadyInit;

  uint16 constant public bscChainID = 0x0060;

  address public constant VALIDATOR_CONTRACT_ADDR = 0x0000000000000000000000000000000000001000;

  address public constant NOMINATION_VOTE_ADDR = 0x0000000000000000000000000000000000003000;

  address public constant SLASH_CONTRACT_ADDR = 0x0000000000000000000000000000000000001001;

  //INIT_VALIDATORSET_BYTES加在这
  bytes public constant INIT_VALIDATORSET_BYTES = hex"f84580f842f84094f9056de9c0c6e8fC3097c3612110641190e0C37b94f9056de9c0c6e8fC3097c3612110641190e0C37b94f9056de9c0c6e8fC3097c3612110641190e0C37b64";

  //创世节点初始化验证
  address public constant GENESIS_NODE1 = 0x1197Ce55f1199C4b5aBab079EBBA7715B7d4aD3F;
  address public constant GENESIS_NODE2 = 0xBda7F006FE37A791ACB4c0A543581e470934498A;
  address public constant GENESIS_NODE3 = 0xF588A47781041644ae6D9A657A6eEe712F7936D6;
  address public constant GENESIS_NODE4 = 0x2719a48598C7bb082a1b485f5e9582b9315ec397;
  address public constant GENESIS_NODE5 = 0x6c67c4B4F082343516372b096899FB48DD4dAB79;
  address public constant GENESIS_NODE6 = 0xD4F607AEF8cb84A2bFAb05F185d3941D55f73bfC;
  
  address public constant GENESIS_ADMIN = 0x74CA05E2B40Fd15c1819583eA63d87C91A1747C6;
  //创世节点初始化收益地址
  address public constant GENESIS_WITHDARW1 = 0x09D70836D8daf81a1d9Ea14A7fddf97C1f872f34;
  address public constant GENESIS_WITHDARW2 = 0x44931BD462c806876c7339Ea0809d1Ab7F0397e2;
  address public constant GENESIS_WITHDARW3 = 0xE10f99BbD766b496343504f46d09c48c7616C9F6;
  address public constant GENESIS_WITHDARW4 = 0x59d38A9AAB6CA9dd2B43fBeF45Fc29EE8d1C90c3;
  address public constant GENESIS_WITHDARW5 = 0x5B1711c6b6e1fEe92eA478230cff05B9d6363e16;
  address public constant GENESIS_WITHDARW6 = 0x96fA4c7dE0Dc1F89aD70b71773F3d56BE0b91b77;
  
  modifier onlyCoinbase() {
    require(msg.sender == block.coinbase, "the message sender must be the block producer");
    _;
  }

  modifier onlyNotInit() {
    require(!alreadyInit, "the contract already init");
    _;
  }

  modifier onlyInit() {
    require(alreadyInit, "the contract not init yet");
    _;
  }

  modifier onlyNominationVoteContract(){
    require(msg.sender == NOMINATION_VOTE_ADDR, "the message sender must be NominationVote contract");
    _;
  }
  
  modifier onlyValidatorContract() {
    require(msg.sender == VALIDATOR_CONTRACT_ADDR, "the message sender must be validatorSet contract");
    _;
  }

  modifier onlySlash() {
    require(msg.sender == SLASH_CONTRACT_ADDR, "the message sender must be slash contract");
    _;
  }

  // Not reliable, do not use when need strong verify
  function isContract(address addr) internal view returns (bool) {
    uint size;
    assembly { size := extcodesize(addr) }
    return size > 0;
  }
}
