//
//  VCHtlcList.m
//  oplayer
//
//  Created by SYALON on 13-10-23.
//
//

#import "VCHtlcList.h"
#import "VCSearchNetwork.h"
#import "VCImportAccount.h"
#import "BitsharesClientManager.h"
#import "ViewActionsCell.h"
#import "OrgUtils.h"
#import "ScheduleManager.h"
#import "MyPopviewManager.h"

enum
{
    kVcSubFromAndTo = 0,
    kVcSubAssetAmount,
    kVcSubPreimageLengthAndHashType,
    kVcSubPreimageHash,
    kVcSubActions,
    
    kVcSubMax
};

@interface VCHtlcList ()
{
    NSDictionary*           _fullAccountInfo;
    BOOL                    _isSelfAccount;
    
    __weak VCBase*          _owner;         //  REMARK：声明为 weak，否则会导致循环引用。
    
    UITableViewBase*        _mainTableView;
    NSMutableArray*         _dataArray;
    
    UILabel*                _lbEmpty;
}

@end

@implementation VCHtlcList

-(void)dealloc
{
    _owner = nil;
    _dataArray = nil;
    _lbEmpty = nil;
    if (_mainTableView){
        [[IntervalManager sharedIntervalManager] releaseLock:_mainTableView];
        _mainTableView.delegate = nil;
        _mainTableView = nil;
    }
    _fullAccountInfo = nil;
}

- (id)initWithOwner:(VCBase*)owner fullAccountInfo:(NSDictionary*)accountInfo
{
    self = [super init];
    if (self){
        _owner = owner;
        _fullAccountInfo = accountInfo;
        _dataArray = [NSMutableArray array];
        _isSelfAccount = [[WalletManager sharedWalletManager] isMyselfAccount:_fullAccountInfo[@"account"][@"name"]];
    }
    return self;
}

- (void)onQueryUserHTLCsResponsed:(NSArray*)data_array
{
    //  更新数据
    [_dataArray removeAllObjects];
    //  TODO:2.1
    if (data_array && [data_array count] > 0){
//        for (id vesting in data_array) {
//            id oid = [vesting objectForKey:@"id"];
//            assert(oid);
//            if (!oid){
//                continue;
//            }
//            //  略过总金额为 0 的待解冻金额对象。
//            if ([[[vesting objectForKey:@"balance"] objectForKey:@"amount"] unsignedLongLongValue] == 0){
//                continue;
//            }
//            //  linear_vesting_policy = 0,
//            //  cdd_vesting_policy
//            if ([[[vesting objectForKey:@"policy"] objectAtIndex:0] integerValue] == 1){
//                id name = [nameHash objectForKey:oid] ?: NSLocalizedString(@"kVestingCellNameCustomVBO", @"自定义解冻金额");
//                id m_vesting = [vesting mutableCopy];
//                [m_vesting setObject:name forKey:@"kName"];
//                [_dataArray addObject:[m_vesting copy]];
//            }else{
//                //  TODO:fowallet 1.7 暂时不支持 linear_vesting_policy
//            }
//        }
    }
    [_dataArray addObjectsFromArray:data_array];
    
    //  根据ID降序排列
    if ([_dataArray count] > 0){
        [_dataArray sortUsingComparator:(^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
            NSInteger id1 = [[[[obj1 objectForKey:@"id"] componentsSeparatedByString:@"."] lastObject] integerValue];
            NSInteger id2 = [[[[obj2 objectForKey:@"id"] componentsSeparatedByString:@"."] lastObject] integerValue];
            return id2 - id1;
        })];
    }
    
    //  更新显示
    _mainTableView.hidden = [_dataArray count] == 0;
    _lbEmpty.hidden = !_mainTableView.hidden;
    if (!_mainTableView.hidden){
        [_mainTableView reloadData];
    }
}

- (void)queryUserHTLCs
{
    ChainObjectManager* chainMgr = [ChainObjectManager sharedChainObjectManager];
    [_owner showBlockViewWithTitle:NSLocalizedString(@"kTipsBeRequesting", @"请求中...")];
    id account = [_fullAccountInfo objectForKey:@"account"];
    id uid = [account objectForKey:@"id"];
    assert(uid);

    //  TODO:2.1 REMARK: !!!!!! 因为core-team的database api尚未完成 !!!!，这里直接从用户明细里获取HTLC编号。
    //  TODO：特别注意：如果API节点配置的账户历史明细太低，可能漏掉部分HTLC对象。又或者用户的账号交易记录太多，HTLC对象也可能被漏掉 。
    //  TODO：后期data base api更新后处理。
    
    NSMutableDictionary* htlc_id_hash = [NSMutableDictionary dictionary];
    GrapheneApi* api_history = [[GrapheneConnectionManager sharedGrapheneConnectionManager] any_connection].api_history;
    [[[api_history exec:@"get_account_history_by_operations" params:@[uid, @[@(ebo_htlc_create)], @0, @100]] then:(^id(id data) {
        id operation_history_objs = [data objectForKey:@"operation_history_objs"];
        if (operation_history_objs && [operation_history_objs isKindOfClass:[NSArray class]] && [operation_history_objs count] > 0){
            for (id op_history in operation_history_objs) {
                id new_object_id = [OrgUtils extractNewObjectIDFromOperationResult:[op_history objectForKey:@"result"]];
                if (new_object_id){
                    [htlc_id_hash setObject:@YES forKey:new_object_id];
                }
            }
        }
        id htlc_id_list = [htlc_id_hash allKeys];
        return [[chainMgr queryAllGrapheneObjects:htlc_id_list] then:(^id(id data_hash) {
            NSMutableDictionary* query_ids = [NSMutableDictionary dictionary];
            //{
            //    conditions =         {
            //        "hash_lock" =             {
            //            "preimage_hash" =                 (
            //                                               2,
            //                                               9464eddceb9e42e757d935e035b2029da01aef237aa98c0f9adb92ee93de8ee0
            //                                               );
            //            "preimage_size" = 64;
            //        };
            //        "time_lock" =             {
            //            expiration = "2019-05-08T11:34:57";
            //        };
            //    };
            //    id = "1.16.62";
            //    transfer =         {
            //        amount = 100000;
            //        "asset_id" = "1.3.0";
            //        from = "1.2.23173";
            //        to = "1.2.23083";
            //    };
            //};
            id htlc_list = [data_hash allValues];
            for (id htlc in htlc_list) {
                id transfer = [htlc objectForKey:@"transfer"];
                assert(transfer);
                [query_ids setObject:@YES forKey:[transfer objectForKey:@"from"]];
                [query_ids setObject:@YES forKey:[transfer objectForKey:@"to"]];
                [query_ids setObject:@YES forKey:[transfer objectForKey:@"asset_id"]];
            }
            //  查询 & 缓存
            return [[chainMgr queryAllGrapheneObjects:[query_ids allKeys]] then:(^id(id data) {
                [_owner hideBlockView];
                [self onQueryUserHTLCsResponsed:htlc_list];
                return nil;
            })];
        })];
    })] catch:(^id(id error) {
        [_owner hideBlockView];
        [OrgUtils makeToast:NSLocalizedString(@"tip_network_error", @"网络异常，请稍后再试。")];
        return nil;
    })];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    
    self.view.backgroundColor = [ThemeManager sharedThemeManager].appBackColor;
    
    //  UI - 列表
    CGRect rect = [self rectWithoutNaviAndPageBar];
    _mainTableView = [[UITableViewBase alloc] initWithFrame:rect style:UITableViewStylePlain];
    _mainTableView.delegate = self;
    _mainTableView.dataSource = self;
    _mainTableView.separatorStyle = UITableViewCellSeparatorStyleNone;  //  REMARK：不显示cell间的横线。
    _mainTableView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_mainTableView];
    
    //  UI - 空
    //  TODO:2.1多语言
    _lbEmpty = [self genCenterEmptyLabel:rect txt:@"没有任何HTLC合约信息"];
    _lbEmpty.hidden = YES;
    [self.view addSubview:_lbEmpty];
}

#pragma mark- TableView delegate method
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [_dataArray count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return kVcSubMax;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    ThemeManager* theme = [ThemeManager sharedThemeManager];
    
    id htlc = [_dataArray objectAtIndex:section];
    
    CGFloat fWidth = self.view.bounds.size.width;
    CGFloat xOffset = tableView.layoutMargins.left;
    
    UIView* myView = [[UIView alloc] init];
    myView.backgroundColor = theme.appBackColor;
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(xOffset, 0, fWidth - xOffset * 2, 28)];
    titleLabel.backgroundColor = [UIColor clearColor];
    titleLabel.textColor = theme.textColorMain;
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.text = [NSString stringWithFormat:@"%@. #%@ ", @(section + 1), htlc[@"id"]];
    
    UILabel *dateLabel = [[UILabel alloc] initWithFrame:CGRectMake(xOffset, 0, fWidth - xOffset * 2, 28)];
    dateLabel.textColor = theme.textColorGray;
    dateLabel.textAlignment = NSTextAlignmentRight;
    dateLabel.backgroundColor = [UIColor clearColor];
    dateLabel.font = [UIFont systemFontOfSize:13];
    
    dateLabel.text = [NSString stringWithFormat:NSLocalizedString(@"kVcOrderExpired", @"%@过期"),
                      [OrgUtils fmtLimitOrderTimeShowString:[[[htlc objectForKey:@"conditions"] objectForKey:@"time_lock"] objectForKey:@"expiration"]]];
    
    [myView addSubview:titleLabel];
    [myView addSubview:dateLabel];
    
    return myView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 28.0f;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    return 16.0f;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
    UIView* myView = [[UIView alloc] init];
    myView.backgroundColor = [UIColor clearColor];
    return myView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.row == kVcSubActions){
        return tableView.rowHeight;
    }
    return 32.0f;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCellBase* cell = [[UITableViewCellBase alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [UIColor clearColor];
    
    id htlc = [_dataArray objectAtIndex:indexPath.section];
    
//    cell.textLabel.text = NSLocalizedString([ary objectAtIndex:indexPath.row], @"");
    cell.textLabel.textColor = [ThemeManager sharedThemeManager].textColorMain;
    
    cell.textLabel.font = [UIFont boldSystemFontOfSize:13.0f];
    cell.detailTextLabel.font = [UIFont boldSystemFontOfSize:13.0f];
    
    //  TODO:2.1多语言
    ThemeManager* theme = [ThemeManager sharedThemeManager];
    ChainObjectManager* chainMgr = [ChainObjectManager sharedChainObjectManager];
    switch (indexPath.row) {
        case kVcSubFromAndTo:
        {
            cell.textLabel.attributedText = [UITableViewCellBase genAndColorAttributedText:@"付款账号 "
                                                                                     value:[[chainMgr getChainObjectByID:[[htlc objectForKey:@"transfer"] objectForKey:@"from"]] objectForKey:@"name"]
                                                                                titleColor:theme.textColorNormal
                                                                                valueColor:theme.textColorMain];
            
            
            cell.detailTextLabel.attributedText = [UITableViewCellBase genAndColorAttributedText:@"收款账号 "
                                                                                           value:[[chainMgr getChainObjectByID:[[htlc objectForKey:@"transfer"] objectForKey:@"to"]] objectForKey:@"name"]
                                                                                      titleColor:theme.textColorNormal
                                                                                      valueColor:theme.textColorMain];
        }
            break;
        case kVcSubAssetAmount:
        {
            BOOL isPay = [_fullAccountInfo[@"account"][@"id"] isEqualToString:[[htlc objectForKey:@"transfer"] objectForKey:@"from"]];
            if (isPay){
                cell.textLabel.attributedText = [UITableViewCellBase genAndColorAttributedText:@"转账类型 "
                                                                                         value:@"付款"
                                                                                    titleColor:theme.textColorNormal
                                                                                    valueColor:theme.sellColor];
            }else{
                cell.textLabel.attributedText = [UITableViewCellBase genAndColorAttributedText:@"转账类型 "
                                                                                         value:@"收款"
                                                                                    titleColor:theme.textColorNormal
                                                                                    valueColor:theme.buyColor];
            }
            cell.detailTextLabel.attributedText = [UITableViewCellBase genAndColorAttributedText:@"转账金额 "
                                                                                           value:[OrgUtils formatAssetAmountItem:[htlc objectForKey:@"transfer"]]
                                                                                      titleColor:theme.textColorNormal
                                                                                      valueColor:theme.textColorMain];
            
            cell.showCustomBottomLine = YES;
        }
            break;
        case kVcSubPreimageLengthAndHashType:
        {
            id size = [[[htlc objectForKey:@"conditions"] objectForKey:@"hash_lock"] objectForKey:@"preimage_size"];
            
            cell.textLabel.attributedText = [UITableViewCellBase genAndColorAttributedText:@"原像长度 "
                                                                                     value:[NSString stringWithFormat:@"%@", size]
                                                                                titleColor:theme.textColorNormal
                                                                                valueColor:theme.textColorMain];
            
            
            NSInteger hash_type = [[[[[htlc objectForKey:@"conditions"] objectForKey:@"hash_lock"] objectForKey:@"preimage_hash"] firstObject] integerValue];
            NSString* hash_type_str = [NSString stringWithFormat:@"未知类型 %@", @(hash_type)];
            switch (hash_type) {
                case EBHHT_RMD160:
                    hash_type_str = @"RIPEMD160";
                    break;
                case EBHHT_SHA1:
                    hash_type_str = @"SHA1";
                    break;
                case EBHHT_SHA256:
                    hash_type_str = @"SHA256";
                    break;
                default:
                    break;
            }
            
            cell.detailTextLabel.attributedText = [UITableViewCellBase genAndColorAttributedText:@"哈希类型 "
                                                                                           value:hash_type_str
                                                                                      titleColor:theme.textColorNormal
                                                                                      valueColor:theme.textColorMain];
        }
            break;
        case kVcSubPreimageHash:
        {
            cell.textLabel.attributedText = [UITableViewCellBase genAndColorAttributedText:@"原像哈希 "
                                                                                     value:[[[[htlc objectForKey:@"conditions"] objectForKey:@"hash_lock"] objectForKey:@"preimage_hash"] lastObject]
                                                                                titleColor:theme.textColorNormal
                                                                                valueColor:theme.textColorMain];
            cell.showCustomBottomLine = YES;
        }
            break;
        case kVcSubActions:
        {
            static NSString* identify = @"id_htlc_actions_cell";
            ViewActionsCell* cell = (ViewActionsCell *)[tableView dequeueReusableCellWithIdentifier:identify];
            if (!cell)
            {
                id buttons = @[
                               @{@"name":@"提取", @"type":@0},
                               @{@"name":@"部署", @"type":@1},
                               ];
                cell = [[ViewActionsCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identify buttons:buttons];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.accessoryType = UITableViewCellAccessoryNone;
                cell.backgroundColor = [UIColor clearColor];
            }
            cell.showCustomBottomLine = YES;
            cell.user_tag = indexPath.section;
            cell.button_delegate = self;
            [cell setItem:htlc];
            return cell;
        }
            break;
        default:
            break;
    }
    
    return cell;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

/**
 *  (public) 计算已经解冻的余额数量。（可提取的）
 */
+ (unsigned long long)calcVestingBalanceAmount:(id)vesting
{
    id policy = [vesting objectForKey:@"policy"];
    assert(policy);
    //  TODO:fowallet 其他的类型不支持。
    assert([[policy objectAtIndex:0] integerValue] == 1);
    id policy_data = [policy objectAtIndex:1];
    assert(policy_data);
    
    //  vesting seconds     REMARK：解冻周期最低1秒。
    NSUInteger vesting_seconds = MAX([[policy_data objectForKey:@"vesting_seconds"] unsignedIntegerValue], 1L);
    
    //  last update timestamp
    NSTimeInterval coin_seconds_earned_last_update_ts = [OrgUtils parseBitsharesTimeString:policy_data[@"coin_seconds_earned_last_update"]];
    NSTimeInterval now_ts = [[NSDate date] timeIntervalSince1970];
    
    //  my balance & already earned seconds
    unsigned long long total_balance_amount = [[[vesting objectForKey:@"balance"] objectForKey:@"amount"] unsignedLongLongValue];
    unsigned long long coin_seconds_earned = [[policy_data objectForKey:@"coin_seconds_earned"] unsignedLongLongValue];
    
    //  recalc real 'coin_seconds_earned' value
    unsigned long long final_earned = coin_seconds_earned;
    if (now_ts > coin_seconds_earned_last_update_ts){
        unsigned long long delta_seconds = (unsigned long long)(now_ts - coin_seconds_earned_last_update_ts);
        unsigned long long delta_coin_seconds = total_balance_amount * delta_seconds;
        unsigned long long coin_seconds_earned_max = total_balance_amount * vesting_seconds;
        final_earned = MIN(coin_seconds_earned + delta_coin_seconds, coin_seconds_earned_max);
    }
    
    unsigned long long withdraw_max = (unsigned long long)floor(final_earned / (double)vesting_seconds);
    assert(withdraw_max <= total_balance_amount);
    
    return withdraw_max;
}

/**
 *  事件 - 提取待解冻金额
 */
- (void)onButtonClicked_Withdraw:(UIButton*)button
{
    assert(_isSelfAccount);
    
    id vesting = [_dataArray objectAtIndex:button.tag];
    NSLog(@"vesting : %@", vesting[@"id"]);
    
    id policy = [vesting objectForKey:@"policy"];
    assert(policy);
    //  TODO:fowallet 其他的类型不支持。
    assert([[policy objectAtIndex:0] integerValue] == 1);
    id policy_data = [policy objectAtIndex:1];
    id start_claim = [policy_data objectForKey:@"start_claim"];
    NSTimeInterval start_claim_ts = [OrgUtils parseBitsharesTimeString:start_claim];
    NSTimeInterval now_ts = [[NSDate date] timeIntervalSince1970];
    if (now_ts <= start_claim_ts){
        id s = [OrgUtils getDateTimeLocaleString:[NSDate dateWithTimeIntervalSince1970:start_claim_ts]];
        [OrgUtils makeToast:[NSString stringWithFormat:NSLocalizedString(@"kVestingTipsStartClaim", @"该笔金额在 %@ 之后方可提取。"), s]];
        return;
    }
    
    //  计算可提取数量
    unsigned long long withdraw_available = [[self class] calcVestingBalanceAmount:vesting];
    if (withdraw_available <= 0){
        [OrgUtils makeToast:NSLocalizedString(@"kVestingTipsAvailableZero", @"没有可提取数量，请等待。")];
        return;
    }
    
    //  ----- 准备提取 -----
    
    //  1、判断手续费是否足够。
    id fee_item =  [[ChainObjectManager sharedChainObjectManager] getFeeItem:ebo_vesting_balance_withdraw full_account_data:_fullAccountInfo];
    if (![[fee_item objectForKey:@"sufficient"] boolValue]){
        [OrgUtils makeToast:NSLocalizedString(@"kTipsTxFeeNotEnough", @"手续费不足，请确保帐号有足额的 BTS/CNY/USD 用于支付网络手续费。")];
        return;
    }
    
    //  2、解锁钱包or账号
    [_owner GuardWalletUnlocked:NO body:^(BOOL unlocked) {
        if (unlocked){
            [self processWithdrawVestingBalanceCore:vesting
                                  full_account_data:_fullAccountInfo
                                           fee_item:fee_item
                                 withdraw_available:withdraw_available];
        }
    }];
}


- (void)processWithdrawVestingBalanceCore:(id)vesting_balance
                        full_account_data:(id)full_account_data
                                 fee_item:(id)fee_item
                       withdraw_available:(unsigned long long)withdraw_available
{
    assert(vesting_balance);
    assert(full_account_data);
    assert(fee_item);
    id balance_id = vesting_balance[@"id"];
    
    id balance = vesting_balance[@"balance"];
    assert(balance);
    id account = [full_account_data objectForKey:@"account"];
    assert(account);
    
    id uid = [account objectForKey:@"id"];
    
    id op = @{
              @"fee":@{@"amount":@0, @"asset_id":fee_item[@"fee_asset_id"]},
              @"vesting_balance":balance_id,
              @"owner":uid,
              @"amount":@{@"amount":@(withdraw_available), @"asset_id":balance[@"asset_id"]}
              };
    
    //  确保有权限发起普通交易，否则作为提案交易处理。
    [_owner GuardProposalOrNormalTransaction:ebo_vesting_balance_withdraw
                       using_owner_authority:NO invoke_proposal_callback:NO
                                      opdata:op
                                   opaccount:account
                                        body:^(BOOL isProposal, NSDictionary *proposal_create_args)
     {
         assert(!isProposal);
         [_owner showBlockViewWithTitle:NSLocalizedString(@"kTipsBeRequesting", @"请求中...")];
         [[[[BitsharesClientManager sharedBitsharesClientManager] vestingBalanceWithdraw:op] then:(^id(id data) {
             [_owner hideBlockView];
             [OrgUtils makeToast:[NSString stringWithFormat:NSLocalizedString(@"kVestingTipTxVestingBalanceWithdrawFullOK", @"待解冻金额 %@ 提取成功。"), balance_id]];
             //  [统计]
             [Answers logCustomEventWithName:@"txVestingBalanceWithdrawFullOK" customAttributes:@{@"account":uid}];
             //  刷新
             [self queryUserHTLCs];
             return nil;
         })] catch:(^id(id error) {
             [_owner hideBlockView];
             [OrgUtils makeToast:NSLocalizedString(@"kTipsTxRequestFailed", @"请求失败，请稍后再试。")];
             //  [统计]
             [Answers logCustomEventWithName:@"txVestingBalanceWithdrawFailed" customAttributes:@{@"account":uid}];
             return nil;
         })];
     }];
}

/**
 *  提取/扩展/部署等按钮点击。
 */
- (void)onButtonClicked:(ViewActionsCell*)cell infos:(id)infos
{
    id htlc = [_dataArray objectAtIndex:cell.user_tag];
    assert(htlc);
}

@end