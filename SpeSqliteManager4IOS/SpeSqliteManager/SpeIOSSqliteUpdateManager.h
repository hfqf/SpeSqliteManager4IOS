/*
 * @Author: user.email
 * @Date: 2023-02-03 15:25:07
 * @LastEditors: user.email
 * @LastEditTime: 2023-02-19 11:54:56
 * @FilePath: /SpeSqliteManager/SpeSqliteManager/SpeSqliteManager/SpeIOSSqliteUpdateManager.h
 * @Description: 
 * 
 * Copyright (c) 2023 by hfqf123@126.com, All Rights Reserved. 
 */
//
//  Created by Points on 15-04-03.
//  Copyright (c) 2015年 Points. All rights reserved.
//

#import <Foundation/Foundation.h>
#define SINGLETON_FOR_HEADER(className) \
+ (className *)sharedInstance;

//单例实现的公用函数
#define SINGLETON_FOR_CLASS(className) \
+ (className *)sharedInstance { \
static className *shared = nil; \
static dispatch_once_t onceToken; \
dispatch_once(&onceToken, ^{ \
shared = [[self alloc] init]; \
}); \
return shared; \
}



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
