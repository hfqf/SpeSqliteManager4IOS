# SpeSqliteManager
一个用来管理iOS数据自动升级的管理类

SpeSqliteUpdateManager类和SpeSqlSetting.plist一起用来控制本地数据的创建和升级功能。升级功能基于应用每次升级后，沙盒的document中的数据不变做的。
说明:
1.目前写的逻辑只是用来只创建了一个db文件。如果配置创建多个db文件，请注意。
2.关于plist:
  1.dbName:是保存到沙盒的数据库文件的名称。
  2.dbVersion:数据库版本号,判断本地数据库文件是否升级就通过此key。
  3.dbTables:想要创建的表名,每个表名下是具体的字段。
  4.上面3个字段名最好不要改，如果修改了话，连同程序里的宏也请同时修改下。
3.对于已经已使用plist的应用，注意plist中的值不要乱改动。
4.修改表时:
  1.不用的表和字段作为冗余表和字段,不删。

使用方法: 
直接调用[SqliteDataManager sharedInstance]即可,可自动创建和升级数据库。
