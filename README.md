# SpeSqliteManager4IOS

一个轻量级管理iOS数据自动升级的管理类
#### **设计亮点**
1.通过SpeSqliteUpdateManager类和SpeSqlSetting.plist一起用来控制本地数据的创建和升级功能。

2.以静制动:新增数据库表、字段、删除表都是修改plist即可，保持代码稳定性。

3.提供加密/非加密两种数据库操作方式，根据需求灵活配置一个宏即可。

4.由非加密升级为加密方式，手动配置下加密版本号，即可自动提供数据迁移。

#### 使用说明
1.目前写的逻辑只是用来只创建了一个db文件。

2.关于plist:
 *  1.dbName:是保存到沙盒的数据库文件的名称。
 *  2.dbVersion:数据库版本号,判断本地数据库文件是否升级就通过此key。
 *  3.dbTables:想要创建的表名,每个表名下是具体的字段。
 *  4.上面3个字段名最好不要改，如果修改了话，连同程序里的宏也请同时修改下。

3.对于已经已使用plist的应用，注意plist中的值不要乱改动。

4.修改表时:1.不用的表和字段作为冗余表和字段,不删。

#### 关键代码:
1.plist
```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>dbName</key>
	<string>local.db</string>
	<key>dbVersion</key>
	<integer>1</integer>
	<key>app</key>
	<array>
		<dict>
			<key>chat</key>
			<array>
				<dict>
					<key>id</key>
					<string>INTEGER PRIMARY KEY AUTOINCREMENT</string>
				</dict>
				<dict>
					<key>uid</key>
					<string>TEXT</string>
				</dict>
			</array>
		</dict>
</dict>
</plist>
```
2.SpeIOSSqliteUpdateManager(核心管理类)
```

#import "SpeEncryptDefine.h"
#if ENCRPTYED
    #import <SQLCipher/sqlite3.h>
#else
    #import <sqlite3.h>
#endif

@interface SpeIOSSqliteUpdateManager : NSObject
{
    sqlite3         *m_db;
    NSDictionary    *m_sqlSettingDic;//在bundle中的数据库plist，即新plist
    NSDictionary    *m_localSettingDic;//本地的数据库plist
    BOOL            m_appUpdate;//冷启动是否是覆盖安装，如果是需要清除本地总的资源版本号
}

SINGLETON_FOR_HEADER(SpeIOSSqliteUpdateManager)

//创建或升级本地数据库
+(void)createOrUpdateDB;

//db名
+ (NSString *)dbName;

+ (sqlite3 *)db;

- (NSString *)pathLocalDB;

- (NSArray *)arrTables;

-(BOOL)execSql:(NSString *)sql;

- (BOOL)isAppUpdate;
@end
```

```
//
//  Created by Points on 15-04-03.
//  Copyright (c) 2015年 Points. All rights reserved.
//

#define KEY_DB_VERSION @"dbVersion"
#define KEY_DB_NAME    @"dbName"
#define KEY_TABLES     @"dbTables"
#define KEY_LOCAL_NAME @"SpeSqlSetting.plist"

#define KEY_SQL_SETTING_PATH   [[NSBundle bundleForClass:self.class] pathForResource:@"SpeSqlSetting" ofType:@"plist"]

#import "SpeIOSSqliteUpdateManager.h"
#import "SpeIOSSqliteUpdateManager+Backup.h"
#import "SpeDesEncrypt.h"
@implementation SpeIOSSqliteUpdateManager

SINGLETON_FOR_CLASS(SpeIOSSqliteUpdateManager)
#if ENCRPTYED
SQLITE_API int sqlite3_key(sqlite3 *db, const void *pKey, int nKey);
SQLITE_API int sqlite3_rekey(sqlite3 *db, const void *pKey, int nKey);
#endif


- (void)dealloc
{
   
    sqlite3_close(m_db);
}

- (id)init{
    if(self = [super init]){
        m_appUpdate = NO;
        m_sqlSettingDic = [NSDictionary dictionaryWithContentsOfFile:KEY_SQL_SETTING_PATH];
        NSString *database_path = [self pathLocalDB];
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documents = [paths objectAtIndex:0];
        NSString *sqlPath = [documents stringByAppendingFormat:@"/lz/%@",KEY_LOCAL_NAME];
        
        NSString * _document = [documents stringByAppendingFormat:@"/lz"];
        if(![[NSFileManager defaultManager]fileExistsAtPath: _document]){
            [[NSFileManager defaultManager] createDirectoryAtPath:_document withIntermediateDirectories:YES attributes:nil error:nil];
        }

        [self getLocalEncryptedPlist:sqlPath];
        
        NSLog(@"DB路径=%@",database_path);
        if([[NSFileManager defaultManager]fileExistsAtPath:database_path]){
            //已经存在需要判断当前数据库版本是否小于24，如果是就需要走备份数据,再创建新数据库，再插入备份数据流程
            [self startUpgrade];
        }else{
            [self openDB];
        }
        if([self isNeedUpadte]){
            m_appUpdate = YES;
            [self updateLocalDB];
            
#pragma mark  // 两次循环找出被删除的表
            [self dropTheTableDeteted];
            
            [self encryptLoclPlist:sqlPath];
        }
    }
    return self;
}

#pragma mark  drop被删除的表(也就是对比新plist表，在本地沙盒数据库里面不存在的table)
- (void)dropTheTableDeteted{
    /*新plist里面所有的表名*/
    NSMutableArray *m_sqlSettingTables = [NSMutableArray array];
    // 获取plist文件对应的所有的key
    NSArray *m_sqlSettingDic_keys = m_sqlSettingDic.allKeys;
    // 遍历出 所有的value数的元素
    for (NSString *key in m_sqlSettingDic_keys) {
        id id_value = m_sqlSettingDic[key];
        if ([id_value isKindOfClass:[NSArray class]]) {
            NSArray *value_array = (NSArray *)id_value;
            // 把数组里面的内容遍历出来
            for (int i = 0; i<value_array.count; i++) {
                NSDictionary *info = [value_array objectAtIndex:i];
                [m_sqlSettingTables addObject:[info.allKeys firstObject]];
            }
        }
    }
    
    /*本地沙盒里面所有的表名*/
    NSMutableArray *m_localSettingTables = [NSMutableArray array];
    // 获取plist文件对应的所有的key
    NSArray *m_localSettingTables_keys = m_localSettingDic.allKeys;
    // 遍历出 所有的value数的元素
    for (NSString *key in m_localSettingTables_keys) {
        id id_value = m_localSettingDic[key];
        if ([id_value isKindOfClass:[NSArray class]]) {
            NSArray *value_array = (NSArray *)id_value;
            // 把数组里面的内容遍历出来
            for (int i = 0; i<value_array.count; i++) {
                NSDictionary *info = [value_array objectAtIndex:i];
                [m_localSettingTables addObject:[info.allKeys firstObject]];
            }
        }
    }
    
    for (NSString *table_name in m_localSettingTables) {
        if (![m_sqlSettingTables containsObject:table_name]) {
            // drop table 操作
            [self dropTable:table_name];
        }
    }
    
}

#pragma mark - 本地plist加解密
- (void)getLocalEncryptedPlist:(NSString *)sqlPath{
   m_localSettingDic =  [NSDictionary dictionaryWithContentsOfFile:sqlPath];
}

- (void)encryptLoclPlist:(NSString *)sqlPath{
     [m_sqlSettingDic  writeToFile:sqlPath atomically:YES];
}

#define ENCRYPT_VERSION 37 //开始数据库加密的版本号
/// 已经存在需要判断当前数据库版本是否小于24，如果是就需要走备份数据,再创建新数据库，再插入备份数据流程
- (void)startUpgrade{
     if([self currentLocalDBVersion]==ENCRYPT_VERSION){
         [self initDB];
          NSMutableArray *arr = [self startShiftSqlite3Data];
          NSError *error = nil;
          NSString *database_path = [self pathLocalDB];
          [[NSFileManager defaultManager]removeItemAtPath:database_path error:&error];
          if(error){
              
          }else{
              [self openDB];
              [self insertAllWillhiftSqlite3Data:arr];
          }
      }else{
            [self openDB];
      }
}

#define PrivateKey @"xxxxxxxxxx"

- (void)initDB{
        NSString *database_path = [self pathLocalDB];
        if (sqlite3_open([database_path UTF8String], &m_db) != SQLITE_OK){
            sqlite3_close(m_db);
        }
        else{
    
        }
}

- (void)openDB{
      NSString *database_path = [self pathLocalDB];
      if (sqlite3_open([database_path UTF8String], &m_db) != SQLITE_OK){
          sqlite3_close(m_db);
      }
      else{
          NSString *key = PrivateKey;
#if ENCRPTYED
    sqlite3_key(m_db, [key UTF8String], key.length);
#endif
          [self createTable];
      }
}

+ (sqlite3 *)db{
    return  [[SpeIOSSqliteUpdateManager sharedInstance]dbHandle];
}


+(void)createOrUpdateDB{
    [SpeIOSSqliteUpdateManager sharedInstance];
}

+ (NSString *)dbName{
    return [[SpeIOSSqliteUpdateManager sharedInstance]DBName];
}

#pragma mark - speSqlSetting.plist


/*
 * 获取新plist的所有表
 *    @brief
 *
 *    @return
 */
- (NSArray *)arrTables{
    NSMutableArray *_arr = [NSMutableArray array];
    // 获取plist文件对应的所有的key
    NSArray *m_sqlSettingDic_keys = m_sqlSettingDic.allKeys;
    // 遍历出 所有的value数的元素
    for (NSString *key in m_sqlSettingDic_keys) {
        id id_value = m_sqlSettingDic[key];
        if ([id_value isKindOfClass:[NSArray class]]) {
            NSArray *value_array = (NSArray *)id_value;
            // 把数组里面的内容遍历出来
            for (int i = 0; i<value_array.count; i++) {
                NSDictionary *info = [value_array objectAtIndex:i];
                [_arr addObject:info];
            }
        }
    }
    return _arr;
}

/*
 * 获取新plist的所有表
 * @param plistDic plist字段对象
 */
- (NSArray *)arrTables:(NSDictionary *)plistDic {
    
    NSMutableArray *_arr = [NSMutableArray array];
    // 获取plist文件对应的所有的key
    NSArray *m_sqlSettingDic_keys = plistDic.allKeys;
    // 遍历出 所有的value数的元素
    for (NSString *key in m_sqlSettingDic_keys) {
        id id_value = plistDic[key];
        if ([id_value isKindOfClass:[NSArray class]]) {
            NSArray *value_array = (NSArray *)id_value;
            // 把数组里面的内容遍历出来
            for (int i = 0; i<value_array.count; i++) {
                NSDictionary *info = [value_array objectAtIndex:i];
                [_arr addObject:info];
            }
        }
    }
    return _arr;
}

/**
 *
 *    @brief    数据库名
 *
 *    @return DBName
 */
- (NSString *)DBName{
    return m_sqlSettingDic[KEY_DB_NAME];
}

/**
 *    @brief    当前数据库版本号
 *
 *    @return
 */
- (NSInteger )currentDBVersion{
    return [m_sqlSettingDic[KEY_DB_VERSION]integerValue];
}

- (NSInteger )currentLocalDBVersion{
    return [m_localSettingDic[KEY_DB_VERSION]integerValue];
}

/**
 *    @brief    是否需要升级(本地无数据库plist和本地版本号小于bundle的plist的版本号)
 *
 *    @return
 */
- (BOOL)isNeedUpadte{
    NSInteger localDBVersion = [m_localSettingDic[KEY_DB_VERSION]integerValue];
    if(m_localSettingDic == nil){
        return YES;
    }
    return localDBVersion < [self currentDBVersion];
}

/**
 *    @brief    本地数据库plist的路径
 *
 *    @return
 */
- (NSString *)pathLocalDB
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documents = [paths objectAtIndex:0];
    NSString *database_path = [documents stringByAppendingFormat:@"/lz/%@",[self DBName]];
    return database_path;
}

/**
 *    @brief    升级db
 *
 *    @return
 */
- (void)updateLocalDB{
    NSArray *arr = [self arrTables];
    if(arr == nil || arr.count == 0){
        return ;
    }
    NSArray *arrLocal = m_localSettingDic[KEY_TABLES];
    
    //未查询到表数组，说明表本地数据库plist结构已变，需从新plist中读取
    if (!arrLocal) {
        arrLocal = [self arrTables:m_localSettingDic];
    }
    
    if(arrLocal.count == 0){
        return;
    }
    
    [self handleDBMatchNewPlist:arrLocal];
    //新数据库plist数据
    for(NSDictionary *tableDic in arr){
        //新数据库
        /*这边操作基于如下规定:
         //1.plist上的表的字段只增不删
         //2.增加的字段加在最下面
         */
        NSString *tableName = nil;
        int searchCount = 0;
        //第一步先判断新plist的表名是不是本地plist已有,没有的话直接新建表
        for(NSDictionary *localSqlDic in arr){
            NSArray *arrKey = tableDic.allKeys;
            if(arrKey.count > 0){
                tableName = [arrKey firstObject];
            }
            
            if(localSqlDic[tableName] == nil){
                searchCount++;
            }
            else{
                continue;
            }
        }
        //是新表
        if(searchCount == arr.count){
            [self createTable:tableDic];
        }
        else{
            NSArray *newSqlArr = tableDic[tableName];
                for(NSDictionary *localSqlSetDic in arrLocal){
                    if([[localSqlSetDic.allKeys firstObject] isEqualToString:tableName]){
                        NSArray *localSqlArr = localSqlSetDic[tableName];
                        //判断是不是完全一致
                        if([newSqlArr isEqualToArray:localSqlArr]){
                            break;
                        }
                        else{
                            NSArray *addColumn =  [newSqlArr subarrayWithRange:NSMakeRange(localSqlArr.count, newSqlArr.count-localSqlArr.count)];
                            //更新表字段
                            __block  NSMutableString *alterSql = nil;
                            for(NSDictionary *addColumnDic in addColumn){
                                alterSql = [NSMutableString stringWithFormat:@"alter table %@ add column",tableName];
                                [addColumnDic enumerateKeysAndObjectsUsingBlock:^(id newParaKey, id newParaObj, BOOL * __unused stop) {
                                    [alterSql appendFormat:@" %@ %@",newParaKey,newParaObj];
                                    [self execSql:alterSql];
                                }];
                            }
                            break;
                        }
                    }
                }
        }
    }
}

/**
 *    @brief    创建所有表
 *
 *    @return
 */
-(BOOL)createTable{
    NSArray *arr = [self arrTables];
    if(arr == nil || arr.count == 0{
        return NO;
    }
    
    for(NSDictionary *tableDic in arr){
        [self createTable:tableDic];
    }
    return YES;
}

/**
 *    @brief    创建表的具体逻辑
 *
 *    @return
 */
- (void)createTable:(NSDictionary *)tableDic{
    __block  NSMutableString *createSql = [NSMutableString stringWithString:@"CREATE TABLE IF NOT EXISTS"];
    
    [tableDic enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL * __unused stop) {
        NSArray *arrColumn = obj;
        if(arrColumn == nil || arrColumn.count == 0){
            return ;
        }
        
        [createSql appendFormat:@"'%@'(",key];
        
        for(NSDictionary *columnDic in arrColumn){
            [columnDic enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL * __unused stop) {
                
                [createSql appendFormat:@"%@ %@,",key,obj];
            }];
        }
        
        createSql = [NSMutableString stringWithString:[createSql substringToIndex:createSql.length-1]];
        [createSql appendFormat:@")"];
    }];
    [self execSql:createSql];
 }

- (void)dropTable:(NSString *)tableName{
    NSString *dropSql = [NSString stringWithFormat:@"DROP TABLE %@",tableName];
    BOOL result = [self execSql:dropSql];
    if (!result) {
        NSLog(@"drop table %@ 失败",tableName);
    }
}


-(BOOL)execSql:(NSString *)sql{
    char *err = NULL;
    if (sqlite3_exec(m_db, [sql UTF8String], NULL, NULL, &err) != SQLITE_OK){
        NSLog(@"数据库操作:%@失败!====%s",sql,err);
        return NO;
    }
    else{
        NSLog(@"操作数据成功==sql:%@",sql);
    }
    return YES;
}

- (sqlite3 *)dbHandle{
    return m_db;
}


+ (NSDictionary *)dictionaryWithJsonString:(NSString *)jsonString {
    if (jsonString == nil) {
        return nil;
    }
    NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err;
    NSDictionary *dic = [NSJSONSerialization JSONObjectWithData:jsonData
                                                        options:NSJSONReadingMutableContainers
                                                          error:&err];
    if(err) {
        NSLog(@"json解析失败：%@",err);
        return nil;
    }
    return dic;
}

- (NSString *)convert2JSONWithDictionary:(NSDictionary *)dic{
    NSError *err;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dic options:0 error:&err];
    NSString *jsonString;
    if (!jsonData) {
        NSLog(@"%@",err);
    }else{
        jsonString = [[NSString alloc]initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
    NSLog(@"%@",jsonString);
    return jsonString;
}

- (BOOL)isAppUpdate{
    return m_appUpdate;
}
@end


```

3.SpeIOSSqliteUpdateManager+Backup(数据迁移)
```
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

```

```
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


```

4.集成方法:直接调用[SqliteDataManager sharedInstance]即可,可自动创建和升级数据库。
```
[SqliteDataManager sharedInstance]
``` 

#### 使用效果
1.已在生产环境使用多年，效果良好。