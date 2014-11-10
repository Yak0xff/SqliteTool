//
//  PersistenceManager.m
//  PersistenceLite
//
//  Created by Cheng Nick on 12-1-21.
//  Copyright (c) 2012年 mRocker Ltd. All rights reserved.
//

#import "PersistenceManager.h"
#import "PersistenceObject.h"
#import "PersistenceHelper.h" 

@interface PersistenceManager (Private)

- (NSString*)databaseFile;
- (void)checkTable:(Class)class;

@end

@implementation PersistenceManager
@synthesize lock;
+ (PersistenceManager*)sharedManager
{
    static PersistenceManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedInstance = [[PersistenceManager alloc] init];
        // Do any other initialisation stuff here
    });
    
    return sharedInstance;
}

- (id)init {
    self = [super init];
    if (self) {
        if(database == NULL){
            if (!sqlite3_open_v2([[self databaseFile] UTF8String], &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, NULL) == SQLITE_OK) 
            {
                // Even though the open failed, call close to properly clean up resources.
                NSLog(@"Failed to open database with message '%s'.", sqlite3_errmsg(database));
                sqlite3_close(database);
            }
            else
            {
                // Default to UTF-8 encoding
                [self execSQL:@"PRAGMA encoding = \"UTF-8\""];
                
                // Turn on full auto-vacuuming to keep the size of the database down
                // This setting can be changed per database using the setAutoVacuum instance method
                [self execSQL:@"PRAGMA auto_vacuum=1"];
                
            }
        }
        
        tables = [[NSMutableArray alloc] init];
        [self setLock:NO];
    }
    return self;
}

- (BOOL)execSQL:(NSString *)sql
{
    char *error;
	
    if (sqlite3_exec(database,[sql UTF8String] , NULL, NULL, &error) != SQLITE_OK) 
    {
        NSLog(@"Failed to execute SQL '%@' with message '%s'.", sql, error);
		sqlite3_free(error);
        
        return NO;
	}
    
    return YES;
}

#pragma mark - Transaction

- (BOOL)startTransaction
{
    BOOL _result=NO;
    @synchronized(transLock) { 
        if([self lock]){
            BOOL unLock=NO;
            for(int i=0;i<30;i++){
                [NSThread sleepForTimeInterval:1.0];
                if(![self lock]){
                    unLock=YES;
                    break;
                }
            }
            if(!unLock){
                NSException *exception=[NSException exceptionWithName:@"Failed lock Thread" reason:@"PersistenceManager lock not release!" userInfo:nil];
                [exception raise];
            }
        }
        [self setLock:YES];
        [self execSQL:@"BEGIN"];
        _result=YES;
    }      
    return _result;
}

- (BOOL)commitTransaction
{
    NSLog(@"commitTransaction"); 
    BOOL result=NO;
    @try {
        result= [self execSQL:@"COMMIT"];
    } 
    @finally {         
        [self setLock:NO];
    }
}

- (BOOL)rollbackTransaction
{
    NSLog(@"rollbackTransaction");
    BOOL result=NO;
    @try {
          result= [self execSQL:@"ROLLBACK"];
    } 
    @finally {         
        [self setLock:NO];
    }
    return result;
}

#pragma mark - Persistence methods

- (NSInteger)insert:(PersistenceObject*)object
{
#if DEBUG
        NSArray *error=[PersistenceHelper validate:object];
        if(error!=nil){
            NSException *e = [[NSException alloc] initWithName:@"data format error!" reason:nil userInfo:nil];  
            @throw e; 
        }
#endif
    [self checkTable:[object class]];
    
    NSMutableString *insertSQL = [NSMutableString stringWithFormat:@"INSERT INTO %@ (", [PersistenceHelper tableName:[object class]]];
    
    NSMutableString *bindSQL = [NSMutableString string];
    
    NSDictionary *props = [PersistenceHelper fields:[object class]];
    NSArray *transients = [[object class] transients];
    
    for (NSString *propName in props)
    {
        if ([transients containsObject:propName]) continue;
        
        if (![propName isEqualToString:@"_id"]) {
            [insertSQL appendFormat:@"%@, ", [PersistenceHelper columnName:propName]];
            [bindSQL appendString:@"?, "];
        }
    }
    
    [insertSQL setString:[insertSQL substringWithRange:NSMakeRange(0, [insertSQL length]-2)]];
    [bindSQL setString:[bindSQL substringWithRange:NSMakeRange(0, [bindSQL length]-2)]];
    
    [insertSQL appendFormat:@") VALUES (%@)", bindSQL];
    
    sqlite3_stmt *stmt;
    
    int result = sqlite3_prepare_v2( database, [insertSQL UTF8String], -1, &stmt, nil);
    
    int identity = -1;
    
    // if sql statement bound ok, now bind the column values
    if (result == SQLITE_OK)
    {
        [PersistenceHelper mappingToStatement:object statement:stmt];
        
        if (sqlite3_step(stmt) != SQLITE_DONE)
        {
            NSLog(@"Error inserting or updating row");
        }
        else
        {
            identity = 0;
            
            NSString *tableName = [PersistenceHelper tableName:[object class]];
            
            NSString *identityQuery = [NSString stringWithFormat:@"SELECT MAX(_id) FROM %@", tableName];
                                   
            sqlite3_stmt *statement;
        
            int result = sqlite3_prepare_v2(database, [identityQuery UTF8String], -1, &statement, nil);
        
            if (result == SQLITE_OK) 
            {
                if (sqlite3_step(statement) == SQLITE_ROW) 
                {
                    identity = sqlite3_column_int(statement, 0);
                }
            }
            else
            {
                NSLog(@"Error select _id value in table %@", tableName);
            }
        
            sqlite3_finalize(statement);
        }
    }
    else
    {
        NSLog(@"Error preparing save SQL: %s -> %@", sqlite3_errmsg(database), insertSQL);
    }
    
    sqlite3_finalize(stmt);
    
    object._id = identity;
    
    return identity;
}

- (NSInteger)update:(PersistenceObject *)object
{   
#if DEBUG
        NSArray *error=[PersistenceHelper validate:object];
        if(error!=nil){
            NSException *e = [[NSException alloc] initWithName:@"data format error!" reason:nil userInfo:nil]; 
            @throw e; 
        }
#endif
    
    [self checkTable:[object class]];
    
    NSMutableString *updateSQL = [NSMutableString stringWithFormat:@"UPDATE %@ SET ", [PersistenceHelper tableName:[object class]]];
    
    NSDictionary *props = [PersistenceHelper fields:[object class]];
    NSArray *transients = [[object class] transients];
    
    for (NSString *propName in props)
    {
        if ([transients containsObject:propName]) continue;
        
        //NSString *propType = [props objectForKey:propName];
        
        if (![propName isEqualToString:@"_id"]) {
            [updateSQL appendFormat:@"%@=?, ", [PersistenceHelper columnName:propName]];
        }
    }
    
    [updateSQL setString:[updateSQL substringWithRange:NSMakeRange(0, [updateSQL length]-2)]];
    
    [updateSQL appendFormat:@" WHERE _id=%d", [object _id]];
    NSLog(@"Update SQL: %@", updateSQL);
    
    sqlite3_stmt *stmt;
    
    int result = sqlite3_prepare_v2( database, [updateSQL UTF8String], -1, &stmt, nil);
    
    int rows = 0;
    
    // if sql statement bound ok, now bind the column values
    if (result == SQLITE_OK)
    {
        [PersistenceHelper mappingToStatement:object statement:stmt];
        
        if (sqlite3_step(stmt) != SQLITE_DONE)
        {
            NSLog(@"Error inserting or updating row");
        }
        else
        {
            rows = 1;
        }
    }
    else
    {
        NSLog(@"Error preparing save SQL: %s", sqlite3_errmsg(database));
    }
    
    sqlite3_finalize(stmt);
    
    return rows;
}

- (NSInteger)delete:(PersistenceObject *)object
{
    [self checkTable:[object class]];
    
    NSString *deleteSQL = [NSString stringWithFormat:@"DELETE FROM %@ WHERE _id = %d", [PersistenceHelper tableName:[object class]], [object _id]];
    NSLog(@"Delete SQL: %@", deleteSQL);
    
    char *error = NULL;
    int result = sqlite3_exec (database, [deleteSQL UTF8String], NULL, NULL, &error);
    
    int rows = 0;
    
    if (result != SQLITE_OK)
    {
        NSLog(@"Error deleting row in table: %s", error);
    }
    else
    {
        rows = 1;
    }
    
	sqlite3_free(error);
    
    return rows;
}

-(NSInteger)drop:(Class)class{
    NSString *dropSQL = [NSString stringWithFormat:@"DROP TABLE  IF EXISTS %@", [PersistenceHelper tableName:class]];
    NSLog(@"Drop SQL: %@", dropSQL);
    
    char *error = NULL;
    int result = sqlite3_exec (database, [dropSQL UTF8String], NULL, NULL, &error);
    
    int rows = 0;
    
    if (result != SQLITE_OK)
    {
        NSLog(@"Error deleting row in table: %s", error);
    }
    else
    {
        NSString *tableName = [PersistenceHelper tableName:class];
        [tables removeObject:tableName];
        rows = 1;
    }
    
	sqlite3_free(error);
    
    return rows;

}



- (NSArray*)execQuery:(NSString*)sql
{
    NSMutableArray *array = [NSMutableArray array];
    
    sqlite3_stmt *statement;
    
    int result = sqlite3_prepare_v2( database, [sql UTF8String], -1, &statement, NULL);
    
    if (result == SQLITE_OK)
	{
        while (sqlite3_step(statement) == SQLITE_ROW)
		{
            NSMutableDictionary *item = [[NSMutableDictionary alloc] init];
            
            for (int i=0; i <  sqlite3_column_count(statement); i++)
            {
                NSString *columnName = [NSString stringWithUTF8String:sqlite3_column_name(statement, i)];
                
                sqlite3_value* value = sqlite3_column_value(statement, i);
                
                int type = sqlite3_value_type(value);
                
                switch (type) {
                    case SQLITE_TEXT:
                    {
                        const char *colVal = (const char *)sqlite3_column_text(statement, i);
                        NSString *colValString = [NSString stringWithUTF8String:colVal];
                        [item setValue:colValString forKey:columnName];
                        
                        break;
                    }
                    case SQLITE_INTEGER:
                    {
                        long long colVal = sqlite3_column_int64(statement, i);
                        NSNumber *colValInteger = [NSNumber numberWithLongLong:colVal];
                        [item setValue:colValInteger forKey:columnName];
                        break;
                    }
                    case SQLITE_FLOAT:
                    {
                        double colVal = sqlite3_column_double(statement, i);
                        NSNumber *colValDouble = [NSNumber numberWithDouble:colVal];
                        [item setValue:colValDouble forKey:columnName];
                        
                        break;
                    }
                    case SQLITE_NULL:
                    {
                        NSLog(@"Cannot Read Column Value at index: %d", i);
                        break;
                    }
                    default:
                    {
                        NSLog(@"Unknow Column Type: %d", type);
                        break;
                    }
                }
            }
            
            [array addObject:item];
        }
    }
    
    sqlite3_finalize(statement);
    
    return array;
}

- (NSArray*)execQuery:(Class)class sql:(NSString *)sql
{
//    va_list arglist;
//    if (!sql) return nil;
//    va_start(arglist, sql);
//    NSString *sqlString = [[NSString alloc] initWithFormat:sql arguments:arglist];
//    va_end(arglist);
    
    [self checkTable:class];
    
    NSLog(@"%@",sql);
    NSMutableArray *array = [NSMutableArray array];
    
    sqlite3_stmt *statement;
    
    int result = sqlite3_prepare_v2( database, [sql UTF8String], -1, &statement, NULL);
    
    if (result == SQLITE_OK)
	{
        while (sqlite3_step(statement) == SQLITE_ROW)
		{
            PersistenceObject *item = [[class alloc] init];
            
            [PersistenceHelper mappingToObject:statement object:item];
            
            [array addObject:item];
        }
    }
    
    sqlite3_finalize(statement);
    
    return array;
}

- (NSArray*)execQuery:(Class)class selection:(NSString *)selection selectionArgs:(NSArray *)selectionArgs groupBy:(NSString *)groupBy orderBy:(NSString *)orderBy limit:(NSInteger)limit
{
    [self checkTable:class];
    
    NSMutableArray *array = [NSMutableArray array];
    
    NSString *querySQL = [NSString stringWithFormat:@"SELECT * FROM %@ ", [PersistenceHelper tableName:class]];
    
    if (selection) {
        querySQL = [querySQL stringByAppendingFormat:@"WHERE %@", selection];
    }
    
    if (groupBy) {
        querySQL = [querySQL stringByAppendingFormat:@"GROUPBY %@", groupBy];
    }
    
    if (orderBy) {
        querySQL = [querySQL stringByAppendingFormat:@"ORDERBY %@", orderBy];
    }
    
    if (limit) {
        querySQL = [querySQL stringByAppendingFormat:@"LIMIT %d", limit];
    }
    NSLog(@"Query SQL: %@", querySQL);
    
    sqlite3_stmt *statement;
    
    int result = sqlite3_prepare_v2( database, [querySQL UTF8String], -1, &statement, NULL);
    
    if (result == SQLITE_OK)
	{
        // Set selection args
        for (int i = 0; i < [selectionArgs count]; i++) {
            NSObject *value = [selectionArgs objectAtIndex:i];
            
            if([value isKindOfClass:[NSString class]])
            {
                sqlite3_bind_text(statement, i + 1, [(NSString*)value UTF8String], -1, NULL);
            }
            else if([value isKindOfClass:[NSNumber class]])
            {
                sqlite3_bind_double(statement, i + 1, [(NSNumber*)value doubleValue]);
            }
            else if([value isKindOfClass:[NSDate class]])
            {
                sqlite3_bind_int64(statement, i + 1, [(NSDate*)value timeIntervalSince1970]);
            }
            else
            {
                NSLog(@"Unknow Object Type: %@", [value class]);
            }
            
            //sqlite3_bind_value(statement, i + 1, (__bridge_retained sqlite3_value*)value);
        }
        
        while (sqlite3_step(statement) == SQLITE_ROW)
		{
            PersistenceObject *item = [[class alloc] init];
            
            [PersistenceHelper mappingToObject:statement object:item];
            
            [array addObject:item];
        }
    }
    
    sqlite3_finalize(statement);
    
    return array;
}

#pragma mark - Database file

- (NSString*)databaseFile
{
    NSString *appName = [[NSProcessInfo processInfo] processName];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:documentsDirectory])
    {
        [[NSFileManager defaultManager] createDirectoryAtPath:documentsDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSString *databaseName = [NSString stringWithFormat:@"%@.sqlite3", appName];
    NSString *databaseFile = [documentsDirectory stringByAppendingPathComponent:databaseName];
    NSLog(@"Database File: %@", databaseFile);
    
    return databaseFile;
}

#pragma mark - Check Table

- (void)checkTable:(Class)class
{
    NSString *tableName = [PersistenceHelper tableName:class];
    
    if([tables containsObject:tableName]){
        return;
    }
    
    BOOL exist = NO;
	NSString *query = [NSString stringWithFormat:@"pragma table_info(%@);", tableName];
	
    sqlite3_stmt *stmt;
	
    int result = sqlite3_prepare_v2( database,  [query UTF8String], -1, &stmt, nil);
    
    if (result == SQLITE_OK) 
    {
		if (sqlite3_step(stmt) == SQLITE_ROW) exist = YES;
		sqlite3_finalize(stmt);
	}
	
    if (exist) {
        [tables addObject:tableName];
        return;
    }
    
    NSString *ddl = [PersistenceHelper genDDL:class];
    
    char *error = NULL;
    
    result = sqlite3_exec (database, [ddl UTF8String], NULL, NULL, &error);
    
    if (result != SQLITE_OK)
    {
        NSLog(@"Error Message: %s", error);
    }
    else
    {
        [tables addObject:tableName];
    }
    
    //TODO Maybe we can deal indexes later
}

@end
