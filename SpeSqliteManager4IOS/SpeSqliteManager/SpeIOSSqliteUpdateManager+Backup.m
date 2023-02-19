//
//  SpeIOSSqliteUpdateManager+Backup.m
//
//  Created by Points on 2020/5/22.
//

#import "SpeIOSSqliteUpdateManager+Backup.h"


@implementation SpeIOSSqliteUpdateManager (Backup)
#pragma mark -  数据备份及重新插入新数据


/// 获取要备份的数据
- (NSMutableArray *)startShiftSqlite3Data{
    NSArray *arr = [self arrTables];
    NSMutableArray *arrDatas = [self arrWillhiftSqlite3Data:arr];
    return arrDatas;
}

- (NSMutableArray *)arrWillhiftSqlite3Data:(NSArray *)arr{
    NSMutableArray *arrTotal = [NSMutableArray array];
    for(NSDictionary *tableDic in arr){
         NSString *tableName = [tableDic.allKeys firstObject];
        BOOL flag = NULL;
         NSArray *columns = [self filterPrimaryKey:[tableDic.allValues firstObject] hasPrimary:&flag];
         NSMutableArray *arr = [NSMutableArray array];
           @synchronized (self) {
                  NSString *sql = [NSString stringWithFormat:@"SELECT * FROM '%@' ",tableName];
                     sqlite3_stmt * statement;
                  if (sqlite3_prepare_v2(m_db, [sql UTF8String], -1, &statement, nil) == SQLITE_OK){
                         while (sqlite3_step(statement) == SQLITE_ROW){
                             [arr addObject:[self row:statement columns:columns hasPrimary:flag]];
                         }
                     }
                     sqlite3_finalize(statement);
                 }
        [arrTotal addObject:arr];
      }
    return arrTotal;
}

- (NSArray *)filterPrimaryKey:(NSArray *)arrColumns hasPrimary:(BOOL *)hasPrimary{
    NSMutableArray *arr = [NSMutableArray array];
    *hasPrimary = NO;
    for(NSDictionary *value in arrColumns){
        if([[value.allValues firstObject]rangeOfString:@"PRIMARY"].length==0 && [[value.allValues firstObject]rangeOfString:@"primary"].length==0){
            [arr addObject:value];
        }else{
            *hasPrimary = YES;
        }
    }
    return arr;
}

- (NSMutableDictionary *)row:(sqlite3_stmt *) statement columns:(NSArray *)columns  hasPrimary:(BOOL)hasPrimary {
    NSMutableDictionary *data = [NSMutableDictionary dictionary];
    for(NSDictionary *column in columns){
        int index = (int)[columns indexOfObject:column];
        
        if([[column.allKeys firstObject]rangeOfString:@"PRIMARY"].length>0||[[column.allValues firstObject]rangeOfString:@"primary"].length>0){//先判断是否有主键
            
        }else  if([[column.allValues firstObject]isEqualToString:@"TEXT"]){//主键数据不要保存
            char *v = sqlite3_column_text(statement, hasPrimary?(index+1):index);
            NSString *item =  v== NULL ? @"" :[NSString stringWithCString:v  encoding:NSUTF8StringEncoding];
            [data setValue:item forKey:[column.allKeys firstObject]];
        }else if ([[column.allValues firstObject]isEqualToString:@"INTEGER"]){
              int v = sqlite3_column_int(statement, hasPrimary?(index+1):index);
              [data setValue:[NSString stringWithFormat:@"%d",v] forKey:[column.allKeys firstObject]];
        }else if ([[column.allValues firstObject]isEqualToString:@"BLOB"]){
            [data setValue:@"" forKey:[column.allKeys firstObject]];
      }
    }
    return data;
}


/// 插入到新数据库
/// @param arrDatas  之前备份的数据
- (void)insertAllWillhiftSqlite3Data:(NSArray *)arrDatas{
        NSArray *arr = [self arrTables];

        for(NSDictionary *tableDic in arr){
             NSInteger index = [arr indexOfObject:tableDic];
             NSString *tableName = [tableDic.allKeys firstObject];
            BOOL *flag = NULL;
             NSArray *columns = [self filterPrimaryKey:[tableDic.allValues firstObject] hasPrimary:&flag];

            //拼接sql语句
            NSMutableString *sql = [NSMutableString stringWithFormat:@"insert into '%@'",tableName];
            for (NSInteger i=0; i<columns.count; i++) {
                NSDictionary *key = [columns objectAtIndex:i];
                NSString *column = [[key allKeys]firstObject];
                if(i==0){
                    [sql appendFormat:@" (%@,",column];
                }else if (i==columns.count-1){
                    [sql appendFormat:@" %@) values",column];
                }else{
                    [sql appendFormat:@" %@,",column];
                }
            }
            
            NSArray *datasource = [arrDatas objectAtIndex:index];
            [datasource enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSDictionary *data = obj;
                NSMutableString *_sql = [NSMutableString stringWithString:sql];
                for (NSInteger i=0; i<data.allKeys.count; i++) {
                    NSDictionary * _key = [columns objectAtIndex:i];
                    NSString *_column = [[_key allKeys]firstObject];
                    NSDictionary *value = [data objectForKey:_column];
                    if(i==0){
                        [_sql appendFormat:@" ('%@',",value];
                    }else if (i==columns.count-1){
                        [_sql appendFormat:@" '%@')",value];
                    }else{
                        [_sql appendFormat:@" '%@',",value];
                    }
                }
                [self execSql:_sql];
            }];
          }
}

/// 本地plist已更新，db中表字段需同步添加
- (void)handleDBMatchNewPlist:(NSArray *)arrLocal {
    for (NSDictionary *tableDic in arrLocal) {
        NSString *tableName = tableDic.allKeys.firstObject;
        int count = [self getColumnCount:tableName];
        NSArray *array = tableDic[tableName];
        //plist中的数组长度超过数据库中才需要更新
        if (array.count > count) {
            //本地的数据库有更新
            NSArray *addColumn =  [array subarrayWithRange:NSMakeRange(count, array.count-count)];
            //更新表字段
            __block  NSMutableString *alterSql = nil;
            for(NSDictionary *addColumnDic in addColumn)
            {
                alterSql = [NSMutableString stringWithFormat:@"alter table %@ add column",tableName];
                [addColumnDic enumerateKeysAndObjectsUsingBlock:^(id newParaKey, id newParaObj, BOOL * __unused stop) {
                    [alterSql appendFormat:@" %@ %@",newParaKey,newParaObj];
                    [self execSql:alterSql];
                }];
            }
        }
    }
    
}

- (int)getColumnCount:(NSString *)tableName {
    @synchronized (self) {
        NSString *sqlQuery = [NSString stringWithFormat:@"select * from %@",tableName];
        sqlite3_stmt * statement;
        if (sqlite3_prepare_v2(m_db, [sqlQuery UTF8String], -1, &statement, nil) == SQLITE_OK) {
            sqlite3_finalize(statement);
            return sqlite3_column_count(statement);
        }
        return 0;
    }
}

@end

