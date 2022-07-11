pragma solidity 0.6.4;
pragma experimental ABIEncoderV2;

import "./System.sol";
import "./lib/BytesToTypes.sol";
import "./lib/Memory.sol";
import "./lib/SafeMath.sol";
import "./lib/RLPDecode.sol";
import "./lib/CmnPkg.sol";
import "./NominationVote.sol";
import "./SlashIndicator.sol";


contract BSCValidatorSet is  System  {

  using SafeMath for uint256;

  using RLPDecode for *;

  uint256 public constant MAX_NUM_OF_VALIDATORS = 31;

  /*********************** state of the contract **************************/
  Validator[] public currentValidatorSet;
  uint256 public expireTimeSecondGap;
  uint256 public totalInComing;

  // key is the `consensusAddress` of `Validator`,
  // value is the index of the element in `currentValidatorSet`.
  mapping(address =>uint256) public currentValidatorSetMap;

  struct Validator{
    //出块节点
    address consensusAddress;
    //是否是验证人（false表示为验证人或候选,true表示已取消成为验证人或候选）
    bool jailed;
    uint256 incoming;

    //票数，新增
    uint64 votes;
    //分红比例
    int8 ratio;
    //每票奖励
    uint256 reTicket;
    //累计获得的奖励
    uint256 totalInComing;
    //交易总数
    uint64 totaltransactions;
    //打包的区块数
    uint blocks;
    //操作人提现地址
    address feeAddress;
  }

  //这个只记录验证人，不做排序，票数最小的直接替换
  struct ValidatorNode{
    //出块节点
    address consensusAddress;
    //票数
    uint64 votes;
    //当前下标是否已被使用
    bool status;
  }
  ValidatorNode[MAX_NUM_OF_VALIDATORS] public currentValidatorSetNode;
  //记录ValidatorNode下标
  mapping(address =>uint256) public currentNode;

  //当前正在出块的验证人
  //mapping(address => uint256) produceValidatorMap;
  //初始化验证人的数量
  int8 public INITIAL_VALIDATOR;
  event Transfer(address indexed from, address indexed to, uint value);

  /*********************** modifiers **************************/
  modifier noEmptyDeposit() {
    require(msg.value > 0, "deposit value is zero");
    _;
  }

  NominationVote nominationVote;
  SlashIndicator slashIndicator;

  //最近一次提现额度
  uint public lastWithdrawal;

  /*********************** events **************************/
  event deprecatedDeposit(address indexed validator, uint256 amount);
  event validatorDeposit(address indexed validator, uint256 amount);

  /*********************** init **************************/
  function init() external onlyNotInit{
    Validator memory validator;
    ValidatorNode memory validatorNode;
    validator.consensusAddress = GENESIS_NODE1;
    //创世节点默认分红10%
    validator.ratio = 10;
    validator.feeAddress = GENESIS_WITHDARW1;
    validatorNode.consensusAddress = GENESIS_NODE1;
    validatorNode.status = true;
    currentValidatorSet.push(validator);
    currentValidatorSetNode[0] = validatorNode;

    validator.consensusAddress = GENESIS_NODE2;
    //创世节点默认分红10%
    validator.ratio = 10;
    validator.feeAddress = GENESIS_WITHDARW2;
    validatorNode.consensusAddress = GENESIS_NODE2;
    validatorNode.status = true;
    currentValidatorSet.push(validator);
    currentValidatorSetNode[1] = validatorNode;

    validator.consensusAddress = GENESIS_NODE3;
    //创世节点默认分红10%
    validator.ratio = 10;
    validator.feeAddress = GENESIS_WITHDARW3;
    validatorNode.consensusAddress = GENESIS_NODE3;
    validatorNode.status = true;
    currentValidatorSet.push(validator);
    currentValidatorSetNode[2] = validatorNode;

    validator.consensusAddress = GENESIS_NODE4;
    //创世节点默认分红10%
    validator.ratio = 10;
    validator.feeAddress = GENESIS_WITHDARW4;
    validatorNode.consensusAddress = GENESIS_NODE4;
    validatorNode.status = true;
    currentValidatorSet.push(validator);
    currentValidatorSetNode[3] = validatorNode;

    validator.consensusAddress = GENESIS_NODE5;
    //创世节点默认分红10%
    validator.ratio = 10;
    validator.feeAddress = GENESIS_WITHDARW5;
    validatorNode.consensusAddress = GENESIS_NODE5;
    validatorNode.status = true;
    currentValidatorSet.push(validator);
    currentValidatorSetNode[4] = validatorNode;

    validator.consensusAddress = GENESIS_NODE6;
    //创世节点默认分红10%
    validator.ratio = 10;
    validator.feeAddress = GENESIS_WITHDARW6;
    validatorNode.consensusAddress = GENESIS_NODE6;
    validatorNode.status = true;
    currentValidatorSet.push(validator);
    currentValidatorSetNode[5] = validatorNode;

    currentValidatorSetMap[GENESIS_NODE1] = 1;
    currentValidatorSetMap[GENESIS_NODE2] = 2;
    currentValidatorSetMap[GENESIS_NODE3] = 3;
    currentValidatorSetMap[GENESIS_NODE4] = 4;
    currentValidatorSetMap[GENESIS_NODE5] = 5;
    currentValidatorSetMap[GENESIS_NODE6] = 6;
    currentNode[GENESIS_NODE1] = 1;
    currentNode[GENESIS_NODE2] = 2;
    currentNode[GENESIS_NODE3] = 3;
    currentNode[GENESIS_NODE4] = 4;
    currentNode[GENESIS_NODE5] = 5;
    currentNode[GENESIS_NODE6] = 6;
    //初始化节点数量
    INITIAL_VALIDATOR = 6;
    nominationVote = NominationVote(NOMINATION_VOTE_ADDR);
    slashIndicator = SlashIndicator(SLASH_CONTRACT_ADDR);
    alreadyInit = true;
  }

  /**********************以下为新增内容，只能投票合约更新 **********************************/
  //更新验证人数量
  function updateValidatorsNumber(int8 validatorsNumber) external onlyInit onlyNominationVoteContract{
    require(uint256(validatorsNumber) < MAX_NUM_OF_VALIDATORS,"exceeded maximum number of validators");
    require(validatorsNumber >= 3 , "less than 3 validators");
    INITIAL_VALIDATOR = validatorsNumber;
  }
  //更新票数 status为true表示增加，false减少
  function updateVoter(uint64 ballot,address valAddr , bool status) external onlyInit onlyNominationVoteContract{
    uint256 index = currentValidatorSetMap[valAddr];
    require(index > 0,"verifier does not exist");
    Validator storage validator = currentValidatorSet[index-1];
    if(status){
      calculateVoteTicket(validator,ballot);
    }else{
      calculateUnVoteTicket(validator,ballot);
    }
    checkRanking(valAddr,status);
  }

  //更新验证人
  function updateCandidates(address user ,int8 ratio,address feeAddress )external onlyInit onlyNominationVoteContract{
    //判断是否已是候选人
    // uint n = currentValidatorSet.length;
    // bool flag = true;
    // for (uint i = 0 ; i<n ; i ++){
    //     if( currentValidatorSet[i].consensusAddress == user && !currentValidatorSet[i].jailed ){
    //         flag = false;
    //         break;
    //     }
    // }
    // require(flag, "already a candidate");

    //先看缓存表
    uint256 index = currentValidatorSetMap[user];
    if(index <= 0){
      Validator memory validator;
      validator.consensusAddress = user;
      validator.jailed = false;
      //validator.status = true;
      validator.feeAddress = feeAddress;
      validator.ratio = ratio;
      currentValidatorSet.push(validator);
      currentValidatorSetMap[user] = currentValidatorSet.length;
      //判断当前验证人是否还有多的位置
      for(uint i = 0 ; i < uint256(INITIAL_VALIDATOR) ; i++){
        if(!currentValidatorSetNode[i].status){
          ValidatorNode memory validatorNode;
          validatorNode.consensusAddress = user;
          validatorNode.status = true;
          currentValidatorSetNode[i] = validatorNode;
          currentNode[user] = i + 1;
          return;
        }
      }
    }else{
      //判断是否已是候选人
      Validator storage validator = currentValidatorSet[index-1];
      require(validator.jailed, "already a candidate");
      validator.jailed = false;
      validator.ratio = ratio;
      validator.feeAddress = feeAddress;

      //判断当前验证人是否还有多的位置
      for(uint i = 0 ; i < uint256(INITIAL_VALIDATOR) ; i++){
        if(!currentValidatorSetNode[i].status){
          ValidatorNode memory validatorNode;
          validatorNode.consensusAddress = user;
          validatorNode.status = true;
          validatorNode.votes = validator.votes;
          currentValidatorSetNode[i] = validatorNode;
          currentNode[user] = i + 1;
          return;
        }
      }

      //遍历验证人，查找票数最小的下标
      index = getMinVotes();
      //更换位置
      if(validator.votes > currentValidatorSetNode[index].votes){
        //删除旧数据
        delete(currentNode[currentValidatorSetNode[index].consensusAddress]);
        //覆盖写入新的
        ValidatorNode memory validatorNode;
        validatorNode.consensusAddress = user;
        validatorNode.status = true;
        validatorNode.votes = validator.votes;
        currentValidatorSetNode[index] = validatorNode;
        currentNode[user] = index + 1;
      }
    }

  }

  //取消成为验证人
  function cancleCandidates(address user)external onlyInit onlyNominationVoteContract{
    // uint256 n = currentValidatorSet.length;
    // //判断当前用户是否是验证人
    // bool flag = false;
    // uint i = 0;
    // for ( ; i < n ; i++){
    //     if( (currentValidatorSet[i].consensusAddress == user || currentValidatorSet[i].feeAddress == user) && !currentValidatorSet[i].jailed){
    //         currentValidatorSet[i].jailed = true;
    //        // currentValidatorSet[i].status = false;
    //         flag = true;
    //         break;
    //     }
    // }
    // require(flag, "not a candidate"); 
    uint256 index = currentValidatorSetMap[user];
    require(index > 0 , "not a candidate");
    Validator storage validator = currentValidatorSet[index-1];
    validator.jailed = true;
    //判断当前候选人是否是出块节点
    index = currentNode[user];
    if(index > 0){
      uint maxindex;
      bool flag;
      (maxindex,flag) = getMaxVotes();
      require(flag, "validators cannot cancel without candidates");
      //删除旧数据
      delete(currentNode[user]);
      //覆盖写入新的
      ValidatorNode memory validatorNode;
      validatorNode.consensusAddress = currentValidatorSet[maxindex].consensusAddress;
      validatorNode.status = true;
      validatorNode.votes = currentValidatorSet[maxindex].votes;
      currentValidatorSetNode[index-1] = validatorNode;
      currentNode[currentValidatorSet[maxindex].consensusAddress] = index;
    }
  }

  //收益提现
  function withdrawGst(address user , uint256 value)external onlyInit onlyNominationVoteContract{
    address payable payableAddr = payable(user);
    payableAddr.transfer(value);
    emit Transfer(VALIDATOR_CONTRACT_ADDR, user, value);
  }

  //管理员提取金额
  function adminWithdrawGst(address payable admin , uint256 value)external onlyInit onlyNominationVoteContract{
    uint maxValue = getMaxWithdrawal();
    require(value <= maxValue,"超过最大领取额度");
    admin.transfer(value);
    emit Transfer(VALIDATOR_CONTRACT_ADDR, admin, value);
    lastWithdrawal = lastWithdrawal.add(value);
  }

  //更新验证人领取奖励
  function withdrawValidatorGst(address user,uint256 amount)external onlyInit onlyNominationVoteContract{
    uint256 index = currentValidatorSetMap[user];
    if( index <= 0){
      return;
    }
    Validator storage validator = currentValidatorSet[index-1];
    if(validator.incoming <= 0){
      return;
    }
    if( validator.incoming > amount ){
      validator.incoming  = validator.incoming.sub(amount);
    }else{
      validator.incoming = 0;
    }
  }

  //修改分红比
  function changeRatio(address user , int8 ratio)external onlyInit onlyNominationVoteContract{
    uint256 index = currentValidatorSetMap[user];
    require(index > 0 , "验证人不存在");
    Validator storage validator = currentValidatorSet[index-1];
    require(!validator.jailed,"退出竞选后禁止修改分红比");
    validator.ratio = ratio;
  }

  //修改矿工委托人
  function changeFeeaddress(address user ,address feeaddress)external onlyInit onlyNominationVoteContract{
    uint256 index = currentValidatorSetMap[user];
    require(index > 0 , "验证人不存在");
    Validator storage validator = currentValidatorSet[index-1];
    require(!validator.jailed,"退出竞选后禁止修改委托人");
    validator.feeAddress = feeaddress;
  }

    //检查排名变化函数
  function checkRanking(address valAddr , bool status) internal{

    uint256 index = currentValidatorSetMap[valAddr];
    require(index > 0,"verifier does not exist");
    Validator storage validator = currentValidatorSet[index-1];
    if(status){
      //投票，投的人是验证人，排序不更新，直接退出
      if( currentNode[valAddr] > 0){
        return;
      }
       //判断当前验证人是否还有多的位置
      for(uint i = 0 ; i < uint256(INITIAL_VALIDATOR) ; i++){
        if(!currentValidatorSetNode[i].status){
          ValidatorNode memory validatorNode;
          validatorNode.consensusAddress = valAddr;
          validatorNode.status = true;
          validatorNode.votes = validator.votes;
          currentValidatorSetNode[i] = validatorNode;
          currentNode[valAddr] = i + 1;
          return;
        }
      }
      index = getMinVotes();
      //票数大于验证人最小的票数，排行榜有更新
      if(validator.votes > currentValidatorSetNode[index].votes ){
        //删除旧数据
        delete(currentNode[currentValidatorSetNode[index].consensusAddress]);
        //覆盖写入新的
        ValidatorNode memory validatorNode;
        validatorNode.consensusAddress = valAddr;
        validatorNode.status = true;
        validatorNode.votes = validator.votes;
        currentValidatorSetNode[index] = validatorNode;
        currentNode[valAddr] = index + 1;
      }
    }else{
      //如果取消投票取消的不是验证人，排名也不更新
      if( currentNode[valAddr] == 0){
        return;
      }
      index = currentNode[valAddr];
      uint maxindex;
      (maxindex,status) = getMaxVotes();
      //验证人取消投票后比候选人最大票数小，更新
      if(validator.votes < currentValidatorSet[maxindex].votes){
        //删除旧数据
        delete(currentNode[valAddr]);
         //覆盖写入新的
        ValidatorNode memory validatorNode;
        validatorNode.consensusAddress = currentValidatorSet[maxindex].consensusAddress;
        validatorNode.status = true;
        validatorNode.votes = currentValidatorSet[maxindex].votes;
        currentValidatorSetNode[index-1] = validatorNode;
        currentNode[currentValidatorSet[maxindex].consensusAddress] = index;
      }
    }

    
  }

  /*********************** 底层出块调用此接口 **************************/
  function deposit(address valAddr,int transactions) external payable onlyCoinbase onlyInit noEmptyDeposit{
    uint256 value = msg.value;
    uint256 index = currentValidatorSetMap[valAddr];

    if (index>0) {
      Validator storage validator = currentValidatorSet[index-1];
      if (validator.jailed) {
        emit deprecatedDeposit(valAddr,value);
      } else {
        //如果有票数,计算分红,截断的金额由出块节点享受
        if( validator.votes > 0){
          uint256 award = value.mul(uint256(validator.ratio)).div(100);
          value = value.sub(award);
          //更新每票奖励
          calculatePreTicket(validator,award);
        }
        totalInComing = totalInComing.add(value);
        validator.incoming = validator.incoming.add(value);
        validator.totalInComing = validator.totalInComing.add(value);
        validator.totaltransactions += uint64(transactions);
        validator.blocks++;
        emit validatorDeposit(valAddr,value);
      }
    } else {
      // get incoming from deprecated validator;
      emit deprecatedDeposit(valAddr,value);
    }
  }

  /*********************** For slash **************************/
  function misdemeanor(address validator)external onlySlash {
    uint256 index = currentValidatorSetMap[validator];
    if (index <= 0) {
      return;
    }
    // the actually index
    index = index - 1;
    uint256 income = currentValidatorSet[index].incoming;
    currentValidatorSet[index].incoming = 0;
    uint256 rest = currentValidatorSet.length - 1;
    //emit validatorMisdemeanor(validator,income);
    if (rest==0) {
      // should not happen, but still protect
      return;
    }
    //获取正在出块的验证人数量
    rest = 0;
    for(uint i = 0 ; i < currentValidatorSetNode.length ; i++){
      if( currentValidatorSetNode[i].status ){
        rest++;
      }
    }
    if (rest==0) {
      // should not happen, but still protect
      return;
    }
    uint256 averageDistribute = income/rest;
    //验证人数量,奖励不能分给候选人
    int8 amount = 0;
    if (averageDistribute!=0) {
      for (uint i=0;i<index;i++) {
        if( amount >= INITIAL_VALIDATOR){
          break;
        }
        if( !currentValidatorSet[i].jailed ){
          currentValidatorSet[i].incoming = currentValidatorSet[i].incoming + averageDistribute;
          amount++;
        }
      }
      uint n = currentValidatorSet.length;
      for (uint i=index+1;i<n;i++) {
        if( amount >= INITIAL_VALIDATOR){
          break;
        }
        if( !currentValidatorSet[i].jailed ){
          currentValidatorSet[i].incoming = currentValidatorSet[i].incoming + averageDistribute;
          amount++;
        }
      }
    }
    // averageDistribute*rest may less than income, but it is ok, the dust income will go to system reward eventually.
  }

  function felony(address validator)external onlySlash {
    uint256 index = currentValidatorSetMap[validator];
    if (index <= 0) {
      return;
    }
    // the actually index
    index = index - 1;
    uint256 income = currentValidatorSet[index].incoming;
    uint256 rest = currentValidatorSet.length - 1;
    if (rest==0) {
      // will not remove the validator if it is the only one validator.
      currentValidatorSet[index].incoming = 0;
      return;
    }
    //获取正在出块的验证人数量
    rest = 0;
    for(uint i = 0 ; i < currentValidatorSetNode.length ; i++){
      if( currentValidatorSetNode[i].status ){
        rest++;
      }
    }
    if (rest==0) {
      // should not happen, but still protect
      return;
    }
    //emit validatorFelony(validator,income);
    //不用删除，留在缓存表中
    //delete currentValidatorSetMap[validator];
    // It is ok that the validatorSet is not in order.
    // if (index != currentValidatorSet.length-1) {
    //   currentValidatorSet[index] = currentValidatorSet[currentValidatorSet.length-1];
    //   currentValidatorSetMap[currentValidatorSet[index].consensusAddress] = index + 1;
    // }
    //currentValidatorSet.pop();
    //收入清0
    currentValidatorSet[index].incoming = 0;
    currentValidatorSet[index].jailed = true;
    index = currentNode[validator];
    //如果验证人取消了竞选，无需再删
    if(index > 0){
      bool flag;
      uint maxindex;
      (maxindex,flag) = getMaxVotes();
      if(!flag){
        currentValidatorSetNode[index-1].status = false;
      }else{
        //覆盖写入新的
        ValidatorNode memory validatorNode;
        validatorNode.consensusAddress = currentValidatorSet[maxindex].consensusAddress;
        validatorNode.status = true;
        validatorNode.votes = currentValidatorSet[maxindex].votes;
        currentValidatorSetNode[index-1] = validatorNode;
        currentNode[currentValidatorSet[maxindex].consensusAddress] = index;
      }
      delete(currentNode[validator]);
    }
    //投票合约把当前验证人修改
    nominationVote.felonyValidator(validator);

    uint256 averageDistribute = income/rest;
    //验证人数量,奖励不能分给候选人
    int8 amount = 0;
    if (averageDistribute!=0) {
      uint n = currentValidatorSet.length;
      for (uint i=0;i<n;i++) {
        if( amount >= INITIAL_VALIDATOR){
          break;
        }
        if( !currentValidatorSet[i].jailed ){
          currentValidatorSet[i].incoming = currentValidatorSet[i].incoming + averageDistribute;
          amount++;
        }
      }
    }
    // averageDistribute*rest may less than income, but it is ok, the dust income will go to system reward eventually.
  }

  function cleanValidator() external onlyInit onlyNominationVoteContract{
    slashIndicator.clean();
  }

  function getValidators()external view returns(address[] memory) {
    uint n = currentValidatorSetNode.length;
    uint valid = 0;
    for (uint i = 0;i<n;i++) {
      if (currentValidatorSetNode[i].status) {
        valid ++;
      }
    }
    //
    if( valid >= uint256(INITIAL_VALIDATOR)){
      valid = uint256(INITIAL_VALIDATOR);
    }
    address[] memory consensusAddrs = new address[](valid);
    //正常可以用的
    valid = 0;
    //uint n = currentValidatorSet.length;
    for (uint i = 0;i<n;i++) {
      if (currentValidatorSetNode[i].status) {
        consensusAddrs[valid] = currentValidatorSetNode[i].consensusAddress;
        valid ++;
      }
      if( valid >= uint256(INITIAL_VALIDATOR)){
        break;
      }
    }
    return consensusAddrs;
  }

  function getValidatorsInfo()external view returns(Validator[] memory,Validator[] memory,Validator[] memory) {
    uint leng = currentValidatorSet.length;
    //验证人数量
    uint sfVaild = 0;
    //候选人数量
    uint candidateVaild  = 0;
    //非候选人数量
    uint nonCandidateVaild = 0;


    for(uint i = 0 ; i < leng ; i++ ){
     if(currentNode[currentValidatorSet[i].consensusAddress] > 0 && sfVaild < uint256(INITIAL_VALIDATOR)){
       sfVaild++;
     }else if(!currentValidatorSet[i].jailed){
       candidateVaild++;
     }else{
       nonCandidateVaild++;
     }
    }

    Validator[] memory sfValidator = new Validator[](sfVaild);
    Validator[] memory candidate = new Validator[](candidateVaild);
    Validator[] memory nonCandidate = new Validator[](nonCandidateVaild);
    sfVaild = 0;
    candidateVaild = 0;
    nonCandidateVaild = 0;
    for(uint i = 0 ; i < currentValidatorSet.length ; i++){
      if( currentNode[currentValidatorSet[i].consensusAddress] > 0 && sfVaild < uint256(INITIAL_VALIDATOR)){
        sfValidator[sfVaild] = currentValidatorSet[i];
        sfVaild++;
      }else if(!currentValidatorSet[i].jailed){
       candidate[candidateVaild] = currentValidatorSet[i];
       candidateVaild++;
      }else{
        nonCandidate[nonCandidateVaild] = currentValidatorSet[i];
        nonCandidateVaild++;
      }
    }
    // sfVaild = 0;
    // candidateVaild = 0;
    // nonCandidateVaild = 0;
    // for(uint i = 0 ; i < leng ; i++){
    //   if(!currentValidatorSet[i].jailed){
    //     if(sfVaild < uint256(INITIAL_VALIDATOR)){
    //       sfValidator[sfVaild] = currentValidatorSet[i];
    //       sfVaild++;
    //     }else{
    //       candidate[candidateVaild] = currentValidatorSet[i];
    //       candidateVaild++;
    //     }
    //   }else{
    //     nonCandidate[nonCandidateVaild] = currentValidatorSet[i];
    //     nonCandidateVaild++;
    //   }
    // }
    return (sfValidator,candidate,nonCandidate);
  }

  //新增get
  function getReTicket(address valAddr)external view returns(uint256){
    uint256 index = currentValidatorSetMap[valAddr];
    require(index > 0,"verifier does not exist");
    return currentValidatorSet[index-1].reTicket;
  }
  
  function getIncoming(address validator)external view returns(uint256) {
    uint256 index = currentValidatorSetMap[validator];
    if (index<=0) {
      return 0;
    }
    return currentValidatorSet[index-1].incoming;
  }

  //获取当前管理员可提取的最大金额
  function getMaxWithdrawal()public view returns(uint maxWithdrawal) {
    uint length = currentValidatorSet.length;
    uint total; //矿工累积的总收入
    uint incoming; //矿工当前收入
    for(uint i = 0; i < length; i++){
      //总收入和当前收入不等，那就是被惩罚扣款了的。这笔钱管理员可以提
      if(currentValidatorSet[i].incoming != currentValidatorSet[i].totalInComing){
        //分开累加计算防止算法溢出
        total = total.add(currentValidatorSet[i].totalInComing);
        incoming = incoming.add(currentValidatorSet[i].incoming);
      }
    }
    maxWithdrawal = maxWithdrawal.add(total.sub(incoming));
    //扣除上次管理员提取金额，就是当前最大剩余
    maxWithdrawal = maxWithdrawal.sub(lastWithdrawal);
  }

  /*********************** Internal Functions **************************/

  function checkValidatorSet(Validator[] memory validatorSet) private pure returns(bool, string memory) {
    if (validatorSet.length > MAX_NUM_OF_VALIDATORS){
      return (false, "the number of validators exceed the limit");
    }
    for (uint i = 0;i<validatorSet.length;i++) {
      for (uint j = 0;j<i;j++) {
        if (validatorSet[i].consensusAddress == validatorSet[j].consensusAddress) {
          return (false, "duplicate consensus address of validatorSet");
        }
      }
    }
    return (true,"");
  }

   //出块奖励计算每票奖励
  function calculatePreTicket(Validator storage validator , uint256 amount) internal{
    //票数为0后，每票奖励重置
    if(validator.votes == 0){
      validator.reTicket = 0;
    }else{
      validator.reTicket += amount.div(uint256(validator.votes));
    }
  }

  //投票更新每票奖励
  function calculateVoteTicket(Validator storage validator,uint64 ballot) internal{
    validator.votes += ballot;
    //validator.reTicket += amount.div(validator.votes);
   // validator.lastRewardBlock = block.number;
    uint256 index = currentNode[validator.consensusAddress];
    if( index > 0){
      currentValidatorSetNode[index-1].votes += ballot;
    }
  }

  //取消投票更新每票奖励
  function calculateUnVoteTicket(Validator storage validator,uint64 ballot) internal{
    //获取当前用户的票数，测试,正式网通过合约获取
    //uint64 votes = 1;
    require(validator.votes >= ballot,"not enough votes");
    //余票
    validator.votes -= ballot;
    // if(validator.votes == 0){
    //   validator.reTicket = 0;
    // }else{
    //   validator.reTicket = validator.reTicket.add(amount.div(uint256(validator.votes)));
    // }
    uint256 index = currentNode[validator.consensusAddress];
    if( index > 0){
      currentValidatorSetNode[index-1].votes -= ballot;
    }
  }

  //获取验证人票数最小的下标
  function getMinVotes() internal view returns(uint){
    uint index = 0;
    uint minvotes = currentValidatorSetNode[0].votes;
    for(uint i = 1 ; i < currentValidatorSetNode.length ; i++){
      if(minvotes > currentValidatorSetNode[i].votes && currentValidatorSetNode[i].status){
        minvotes = currentValidatorSetNode[i].votes;
        index = i;
      }
    }
    return index;
  }

  //获取候选人票数最大的下标
  function getMaxVotes() internal view returns(uint,bool){
    uint index = 0;
    uint maxvotes = 0;
    bool flag = false;
    for(uint i = 0 ; i < currentValidatorSet.length ; i++){
      if(maxvotes <= currentValidatorSet[i].votes && currentNode[currentValidatorSet[i].consensusAddress] == 0){
        maxvotes = currentValidatorSet[i].votes;
        index = i;
        flag = true;
      }
    }
    return (index,flag);
  }

}
