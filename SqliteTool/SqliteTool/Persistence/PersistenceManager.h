//
//  PersistenceManager.h
//  PersistenceLite
//
//  Created by Cheng Nick on 12-1-21.
//  Copyright (c) 2012年 mRocker Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <sqlite3.h>

@class PersistenceObject;

@interface PersistenceManager : NSObject
{
    sqlite3 *database;
    NSMutableArray *tables;
    BOOL lock;
    NSObject *transLock;
}
@property (nonatomic,assign) BOOL lock;

+ (PersistenceManager*)sharedManager;

- (BOOL)execSQL:(NSString*)sql;

- (BOOL)startTransaction;
- (BOOL)commitTransaction;
- (BOOL)rollbackTransaction;

- (NSInteger)insert:(PersistenceObject*)object;
- (NSInteger)update:(PersistenceObject*)object;
- (NSInteger)delete:(PersistenceObject*)object;
- (NSInteger)drop:(Class)class;

- (NSArray*)execQuery:(NSString*)sql;
- (NSArray*)execQuery:(Class)class sql:(NSString *)sql;
- (NSArray*)execQuery:(Class)class selection:(NSString*)selection selectionArgs:(NSArray*)selectionArgs groupBy:(NSString*)groupBy orderBy:(NSString*)orderBy limit:(NSInteger)limit;

@end
