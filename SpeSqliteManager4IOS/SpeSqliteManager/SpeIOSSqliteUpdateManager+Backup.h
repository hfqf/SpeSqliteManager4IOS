//
//
//  Created by Points on 2020/5/22.
//  SQLCipher无法对老数据加密。方案:备份老数据数据->删除老数据库->新建新数据库->插入备份数据->完成迁移



#import "SpeIOSSqliteUpdateManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface SpeIOSSqliteUpdateManager (Backup)
/// 获取要备份的数据
- (NSMutableArray *)startShiftSqlite3Data;

/// 插入到新数据库
/// @param arrDatas  之前备份的数据
- (void)insertAllWillhiftSqlite3Data:(NSArray *)arrDatas;

/// 处理本地数据库与新的plist的字段不统一的bug
/**
 * @pragma 本地plist的数组
 */
- (void)handleDBMatchNewPlist:(NSArray *)arrLocal;

@end

NS_ASSUME_NONNULL_END
