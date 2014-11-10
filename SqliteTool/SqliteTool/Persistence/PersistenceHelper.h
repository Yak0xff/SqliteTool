//
//  PersistenceHelper.h
//  PersistenceLite
//
//  Created by Cheng Nick on 12-1-16.
//  Copyright (c) 2012年 mRocker Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <sqlite3.h>
 

@class PersistenceObject;

@interface PersistenceHelper : NSObject

@property (nonatomic,strong) NSString *bpk;

+ (NSString*) tableName:(Class)class;

+ (NSString*) columnName:(NSString*)propertyName;
+ (NSString*) propertyName:(NSString*)columnName;

+ (NSDictionary*)fields:(Class)class;

+ (NSString*) genDDL:(Class)class;

+ (void)mappingToStatement:(PersistenceObject*)object statement:(sqlite3_stmt*)statement;

+ (void)mappingToObject:(sqlite3_stmt*)statement object:(PersistenceObject*)object;

+ (NSMutableArray *)validate:(PersistenceObject *)object;

@end
