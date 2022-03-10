pragma solidity 0.6.4;
import "./System.sol";
import "./lib/BytesToTypes.sol";
import "./lib/Memory.sol";
import "./lib/CmnPkg.sol";
import "./lib/RLPEncode.sol";
import "./BSCValidatorSet.sol";

contract SlashIndicator is System{
  using RLPEncode for *;

  uint256 public constant MISDEMEANOR_THRESHOLD = 50;
  uint256 public constant FELONY_THRESHOLD = 300;
  uint256 public constant BSC_RELAYER_REWARD = 1e16;
  uint256 public constant DECREASE_RATE = 4;

  // State of the contract
  address[] public validators;
  mapping(address => Indicator) public indicators;
  uint256 public previousHeight;
  uint256 public  misdemeanorThreshold;
  uint256 public  felonyThreshold;

  BSCValidatorSet bscValidatorSet;

  event validatorSlashed(address indexed validator);
  event indicatorCleaned();
  event paramChange(string key, bytes value);

  event knownResponse(uint32 code);
  event unKnownResponse(uint32 code);
  event crashResponse();

  struct Indicator {
    uint256 height;
    uint256 count;
    bool exist;
  }

  modifier oncePerBlock() {
    require(block.number > previousHeight, "can not slash twice in one block");
    _;
    previousHeight = block.number;
  }

  modifier onlyZeroGasPrice() {
    
    require(tx.gasprice == 0 , "gasprice is not zero");
    
    _;
  }
  
  function init() external onlyNotInit{
    misdemeanorThreshold = MISDEMEANOR_THRESHOLD;
    felonyThreshold = FELONY_THRESHOLD;
    alreadyInit = true;
    bscValidatorSet = BSCValidatorSet(VALIDATOR_CONTRACT_ADDR);
  }

  /*********************** External func ********************************/
  function slash(address validator) external onlyCoinbase onlyInit oncePerBlock onlyZeroGasPrice{
    Indicator memory indicator = indicators[validator];
    if (indicator.exist) {
      indicator.count++;
    } else {
      indicator.exist = true;
      indicator.count = 1;
      validators.push(validator);
    }
    indicator.height = block.number;
    if (indicator.count % felonyThreshold == 0) {
      indicator.count = 0;
      bscValidatorSet.felony(validator);
    } else if (indicator.count % misdemeanorThreshold == 0) {
      bscValidatorSet.misdemeanor(validator);
    }
    indicators[validator] = indicator;
    emit validatorSlashed(validator);
  }


  // To prevent validator misbehaving and leaving, do not clean slash record to zero, but decrease by felonyThreshold/DECREASE_RATE .
  // Clean is an effective implement to reorganize "validators" and "indicators".
  function clean() external  onlyValidatorContract onlyInit{
    if(validators.length == 0){
      return;
    }
    uint i = 0;
    uint j = validators.length-1;
    for (;i <= j;) {
      bool findLeft = false;
      bool findRight = false;
      for(;i<j;i++){
        Indicator memory leftIndicator = indicators[validators[i]];
        if(leftIndicator.count > felonyThreshold/DECREASE_RATE){
          leftIndicator.count = leftIndicator.count - felonyThreshold/DECREASE_RATE;
          indicators[validators[i]] = leftIndicator;
        }else{
          findLeft = true;
          break;
        }
      }
      for(;i<=j;j--){
        Indicator memory rightIndicator = indicators[validators[j]];
        if(rightIndicator.count > felonyThreshold/DECREASE_RATE){
          rightIndicator.count = rightIndicator.count - felonyThreshold/DECREASE_RATE;
          indicators[validators[j]] = rightIndicator;
          findRight = true;
          break;
        }else{
          delete indicators[validators[j]];
          validators.pop();
        }
        // avoid underflow
        if(j==0){
          break;
        }
      }
      // swap element in array
      if (findLeft && findRight){
        delete indicators[validators[i]];
        validators[i] = validators[j];
        validators.pop();
      }
      // avoid underflow
      if(j==0){
        break;
      }
      // move to next
      i++;
      j--;
    }
    emit indicatorCleaned();
  }

  /*********************** query api ********************************/
  function getSlashIndicator(address validator) external view returns (uint256,uint256) {
    Indicator memory indicator = indicators[validator];
    return (indicator.height, indicator.count);
  }

  function encodeSlashPackage(address valAddr) internal view returns (bytes memory) {
    bytes[] memory elements = new bytes[](4);
    elements[0] = valAddr.encodeAddress();
    elements[1] = uint256(block.number).encodeUint();
    elements[2] = uint256(bscChainID).encodeUint();
    elements[3] = uint256(block.timestamp).encodeUint();
    return elements.encodeList();
  }
}