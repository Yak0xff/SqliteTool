 

#import "PersistenceHelper.h"
#import "PersistenceObject.h" 

#import <objc/runtime.h>

@interface PersistenceHelper (Private)

+ (NSString *)nameFilter:(NSString *)name;

@end

@implementation PersistenceHelper
@synthesize bpk=_bpk;
+ (NSString*) tableName:(Class)class
{
    return [self nameFilter:[NSString stringWithUTF8String:class_getName(class)]];
}

+ (NSString*) columnName:(NSString *)propertyName
{
    return [self nameFilter:propertyName];
}

+ (NSString*) propertyName:(NSString *)columnName
{
    BOOL lastWasUnderscore = NO;
    
	NSMutableString *ret = [NSMutableString string];
    
	for (int i=0; i < [columnName length]; i++)
	{
		NSRange sRange = NSMakeRange(i,1);
		NSString *oneChar = [columnName substringWithRange:sRange];
		if ([oneChar isEqualToString:@"_"] && i != 0)   //ignore leading "_"
        {
			lastWasUnderscore = YES;
        }
		else
		{
			if (lastWasUnderscore)
				[ret appendString:[oneChar uppercaseString]];
			else
				[ret appendString:oneChar];
			
			lastWasUnderscore = NO;
		}
	}
    
	return ret;
}

+ (NSDictionary *)fields:(Class)class
{
    // Recurse up the classes, but stop at NSObject. Each class only reports its own properties, not those inherited from its superclass
	NSMutableDictionary *theProps;
	
	if ([class superclass] != [NSObject class])
		theProps = (NSMutableDictionary *)[self fields:[class superclass]];
	else
		theProps = [NSMutableDictionary dictionary];
	
	unsigned int outCount;
    
    objc_property_t *propList = class_copyPropertyList(class, &outCount);
    
    // Loop through properties and add declarations for the create
	for (int i=0; i < outCount; i++)
	{
        objc_property_t oneProp = propList[i];
        
		NSString *propName = [NSString stringWithUTF8String:property_getName(oneProp)];
		NSString *attrs = [NSString stringWithUTF8String:property_getAttributes(oneProp)];
		 
        
        // Read only attributes are assumed to be derived or calculated
		if ([attrs rangeOfString:@",R,"].location == NSNotFound)
		{
			NSArray *attrParts = [attrs componentsSeparatedByString:@","];
			if (attrParts != nil)
			{
				if ([attrParts count] > 0)
				{
					NSString *propType = [[attrParts objectAtIndex:0] substringFromIndex:1];
					[theProps setObject:propType forKey:propName];
				}
			}
		}
    }
    
    free(propList);
    
    return theProps;
}

+ (NSString*) genDDL:(Class)class
{
    NSArray *theTransients = [class transients];
	
    NSMutableString *createSQL = [NSMutableString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (_id INTEGER PRIMARY KEY AUTOINCREMENT",[self tableName:class]];
    
    NSDictionary *properties = [self fields:class];
    
    for (NSString *oneProp in properties)
    { 
        if ([theTransients containsObject:oneProp]) continue;
        
        NSString *propName = [self nameFilter:oneProp];
        
        if (![propName isEqualToString:@"_id"]) {
            NSString *propType = [properties objectForKey:oneProp];
            NSLog(@"Property Name: %@ with Type: %@", propName, propType);
            
            // Integer Types
            if ([propType isEqualToString:@"i"] || // int
                [propType isEqualToString:@"I"] || // unsigned int
                [propType isEqualToString:@"l"] || // long
                [propType isEqualToString:@"L"] || // usigned long
                [propType isEqualToString:@"q"] || // long long
                [propType isEqualToString:@"Q"] || // unsigned long long
                [propType isEqualToString:@"s"] || // short
                [propType isEqualToString:@"S"] || // unsigned short
                [propType isEqualToString:@"B"] )  // bool or _Bool
            {
                [createSQL appendFormat:@", %@ INTEGER", propName];		
            }	
            // Character Types
            else if ([propType isEqualToString:@"c"] ||	// char
                     [propType isEqualToString:@"C"] )  // unsigned char
            {
                [createSQL appendFormat:@", %@ INTEGER", propName];
            }
            else if ([propType isEqualToString:@"f"] || // float
                     [propType isEqualToString:@"d"] )  // double
            {		 
                [createSQL appendFormat:@", %@ REAL", propName];
            }
            else if ([propType hasPrefix:@"@"] ) // Object
            {
                NSString *className = [propType substringWithRange:NSMakeRange(2, [propType length]-3)];
                
                if([className isEqualToString:@"NSString"])
                {
                    [createSQL appendFormat:@", %@ TEXT", propName];
                }
                else if([className isEqualToString:@"NSNumber"])
                {
                    [createSQL appendFormat:@", %@ REAL", propName];
                }
                else if([className isEqualToString:@"NSDate"])
                {
                    [createSQL appendFormat:@", %@ REAL", propName];
                }
                else if([className isEqualToString:@"NSData"])
                {
                    [createSQL appendFormat:@", %@ BLOB", propName];
                }
                else
                {
                    NSLog(@"Unknow Object Type: %@", className);
                }
                //Ignor other object type this time            
            }
        }
    }
    
    [createSQL appendString:@")"];
    
    NSLog(@"Create SQL: %@", createSQL);
    
    return createSQL;
}

+ (void)mappingToStatement:(PersistenceObject *)object statement:(sqlite3_stmt *)statement
{
    NSDictionary *props = [PersistenceHelper fields:[object class]];
    NSArray *transients = [[object class] transients];
    
    int index = 1;
    
    for (NSString *propName in props)
    {
        @try {     
            
        if ([transients containsObject:propName]) continue;
        
        NSString *propType = [props objectForKey:propName];
        
        if (![propName isEqualToString:@"_id"]) {
            id value = [object valueForKey:propName];
            
            if (!value)
            {
                sqlite3_bind_null(statement, index++);
            }
            else if ([propType isEqualToString:@"i"] || // int
                     [propType isEqualToString:@"I"] || // unsigned int
                     [propType isEqualToString:@"l"] || // long
                     [propType isEqualToString:@"L"] || // usigned long
                     [propType isEqualToString:@"q"] || // long long
                     [propType isEqualToString:@"Q"] || // unsigned long long
                     [propType isEqualToString:@"s"] || // short
                     [propType isEqualToString:@"S"] || // unsigned short
                     [propType isEqualToString:@"B"])   // bool
            {
                sqlite3_bind_int64(statement, index++, [value longLongValue]);
            }
            else if ([propType isEqualToString:@"f"] || // float
                     [propType isEqualToString:@"d"] )  // double
            {
                sqlite3_bind_double(statement, index++, [value doubleValue]);
            }
            else if ([propType isEqualToString:@"c"] ||	// char
                     [propType isEqualToString:@"C"] ) // unsigned char
                
            {
                sqlite3_bind_int(statement, index++, [value intValue]);
            }
            else if ([propType hasPrefix:@"@"] ) // Object
            {
                NSString *className = [propType substringWithRange:NSMakeRange(2, [propType length]-3)];
                
                if([className isEqualToString:@"NSString"])
                {   
                    NSLog(@"%@",value);
                    if(![value isKindOfClass:[NSNull class]]){
                            sqlite3_bind_text(statement, index++, [value UTF8String], -1, NULL); 
                    }
                    else
                        sqlite3_bind_text(statement, index++, [@"" UTF8String], -1, NULL);                         
                }
                else if([className isEqualToString:@"NSNumber"])
                {
                    sqlite3_bind_double(statement, index++, [value doubleValue]);
                }
                else if([className isEqualToString:@"NSDate"])
                {
                    sqlite3_bind_double(statement, index++, [value timeIntervalSince1970]);
                }
                else if([className isEqualToString:@"NSData"])
                {
                    sqlite3_bind_blob(statement, index++, [value bytes], [value length], NULL);
                }
                else
                {
                    index++;
                    NSLog(@"Unknow Object Type: %@", className);
                }
            }
        
                
                
        }
            
        }
        @catch (NSException *exception) { 
            NSLog(@"%@",[[exception callStackSymbols] componentsJoinedByString:@"\n"]);
            @throw exception;
        }
    }
}

+ (void)mappingToObject:(sqlite3_stmt *)statement object:(PersistenceObject *)object
{
    NSDictionary *theProps = [self fields:[object class]];
    
    for (int i=0; i <  sqlite3_column_count(statement); i++)
    {
        NSString *columnName = [NSString stringWithUTF8String:sqlite3_column_name(statement, i)];
        
        NSString *propName = [self propertyName:columnName];
        
        NSString *columnType = [theProps valueForKey:propName];
        
        if (!columnType) {
            break;
        }
        
        if ([columnType isEqualToString:@"i"] || // int
            [columnType isEqualToString:@"l"] || // long
            [columnType isEqualToString:@"q"] || // long long
            [columnType isEqualToString:@"s"] || // short
            [columnType isEqualToString:@"B"] || // bool or _Bool
            [columnType isEqualToString:@"I"] || // unsigned int
            [columnType isEqualToString:@"L"] || // usigned long
            [columnType isEqualToString:@"Q"] || // unsigned long long
            [columnType isEqualToString:@"S"])   // unsigned short
        {
            long long value = sqlite3_column_int64(statement, i);
            NSNumber *colValue = [NSNumber numberWithLongLong:value];
            [object setValue:colValue forKey:propName];
        }
        else if ([columnType isEqualToString:@"f"] || // float
                 [columnType isEqualToString:@"d"] )  // double
        {
            double value = sqlite3_column_double(statement, i);
            NSNumber *colVal = [NSNumber numberWithDouble:value];
            [object setValue:colVal forKey:propName];
        }
        else if ([columnType isEqualToString:@"c"] ||	// char
                 [columnType isEqualToString:@"C"] ) // unsigned char
        {
            int value = sqlite3_column_int(statement, i);
            NSNumber *colVal = [NSNumber numberWithInt:value];
            [object setValue:colVal forKey:propName];
        }
        else if ([columnType hasPrefix:@"@"] ) // Object
        {
            NSString *className = [columnType substringWithRange:NSMakeRange(2, [columnType length]-3)];
            
            if([className isEqualToString:@"NSString"])
            {
                const char *colVal = (const char *)sqlite3_column_text(statement, i);
                
                if (colVal != nil)
                {
                    NSString *colValString = [NSString stringWithUTF8String:colVal];
                    [object setValue:colValString forKey:propName];
                }
            }
            else if([className isEqualToString:@"NSNumber"])
            {
                double value = sqlite3_column_double(statement, i);
                NSNumber *colVal = [NSNumber numberWithDouble:value];
                [object setValue:colVal forKey:propName];
            }
            else if([className isEqualToString:@"NSDate"])
            {
                double value = sqlite3_column_double(statement, i);
                NSDate *colValue = [NSDate dateWithTimeIntervalSince1970:value];
                [object setValue:colValue forKey:propName];
            }
            else if([className isEqualToString:@"NSData"])
            {
                const void* value = sqlite3_column_blob(statement, i);
                if (value != NULL)
                {
                    int length = sqlite3_column_bytes(statement, i);   
                    NSData *colValue = [NSData dataWithBytes:value length:length];
                    [object setValue:colValue forKey:propName];
                }
            }
            else
            {   
                NSLog(@"Unknow Object Type: %@", className);
            }
        }
    }
}

#pragma mark - Private methods

+ (NSString *)nameFilter:(NSString *)name
{
    NSMutableString *ret = [NSMutableString string];
    
	for (int i = 0; i < name.length; i++)
	{
		NSRange range = NSMakeRange(i, 1);
		NSString *oneChar = [name substringWithRange:range];
		if ([oneChar isEqualToString:[oneChar uppercaseString]] && i > 0)
			[ret appendFormat:@"_%@", [oneChar lowercaseString]];
		else
			[ret appendString:[oneChar lowercaseString]];
	}
    
    return ret;
}

+ (NSMutableArray *)validate:(PersistenceObject *)object
{
    NSDictionary *props = [PersistenceHelper fields:[object class]];
    NSArray *transients = [[object class] transients];
    NSMutableArray *error=[[NSMutableArray alloc] init];
    [error addObject:[[NSMutableString alloc] initWithString:@"---- error data format ----"]];
    [error addObject:[@"table name:" stringByAppendingString:[PersistenceHelper tableName:[object class]]]];
     
    @try {
        
        for (NSString *propName in props)
        {
            
            if ([transients containsObject:propName]) continue;
            
            NSString *propType = [props objectForKey:propName];
            id value = [object valueForKey:propName];
            
            if ([propType hasPrefix:@"@"] ){
                NSString *className = [propType substringWithRange:NSMakeRange(2, [propType length]-3)];
                
                if([value isKindOfClass:[NSNull class]]||value==nil)
                    continue;
                
                if([className isEqualToString:@"NSString"])
                {
                    if([value isKindOfClass:[NSString class]])
                       continue;
                }
                else if([className isEqualToString:@"NSNumber"])
                {
                    if([value isKindOfClass:[NSNumber class]])
                        continue;
                }
                else if([className isEqualToString:@"NSDate"])
                {
                    if([value isKindOfClass:[NSDate class]])
                        continue;
                }
                else if([className isEqualToString:@"NSData"])
                {
                    if([value isKindOfClass:[NSData class]])
                        continue;
                }else {
                    continue;
                }
 
                
                NSString *valueClassName=[NSString stringWithUTF8String:class_getName([value class])];
                
                
                
                NSMutableString *string=[[NSMutableString alloc] init];
                [string appendString:@"propName ["];
                [string appendString:propName];
                [string appendString:@"]: error data type "];
                [string appendString:@"["];
                [string appendString:valueClassName];
                [string appendString:@"], need data type "];
                [string appendString:@"["];
                [string appendString:className];
                [string appendString:@"] or this subclass type!"]; 
                [error addObject:string];
            }
            
        }
    }
    @catch (NSException *exception) {       
        [error addObject:[[exception callStackSymbols] componentsJoinedByString:@"\n"]];
    } 
    [error addObject:[[NSMutableString alloc] initWithString:@"----- error data end -----"]];
    if(error.count>3)
        return error;
    else { 
        return nil;
    }
}


@end
