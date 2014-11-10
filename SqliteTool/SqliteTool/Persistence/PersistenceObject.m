 

#import "PersistenceObject.h" 
#import "PersistenceManager.h"
#import "PersistenceHelper.h"

@implementation PersistenceObject
@synthesize _id,identity;

+ (NSArray*)transients
{
    return [NSArray array];
}

+ (NSArray *)list{
    
    PersistenceManager *manager = [PersistenceManager sharedManager]; 
    
    NSArray *result = [manager execQuery:[self class] sql:[NSString stringWithFormat:@"select * from %@",[PersistenceHelper tableName:[self class]]]];
    
    return result;
}

+ (NSArray *)list:(NSInteger)page PageSize:(NSInteger)pageSize{
    
    PersistenceManager *manager = [PersistenceManager sharedManager]; 
    
    NSArray *result = [manager execQuery:[self class] sql:[NSString stringWithFormat:@"select * from %@ limit %d,%d",[PersistenceHelper tableName:[self class]],page*pageSize,pageSize]];
    
    return result;
}

+(NSUInteger)count{
    PersistenceManager *manager = [PersistenceManager sharedManager];  
     
    NSArray *counts = [manager execQuery:[NSString stringWithFormat:@"select count(*) as count from %@",[PersistenceHelper tableName:[self class]]]]; 
    NSUInteger _count=0;
    if([counts count]>0){ 
        _count=((NSNumber *)[((NSDictionary *)[counts objectAtIndex:0]) objectForKey:@"count"]).intValue;      
    }
    return _count; 
}
- (id)fetchWithIdentity{
    
    PersistenceManager *manager = [PersistenceManager sharedManager];
    
    NSArray *result = [manager execQuery:[self class] sql:[NSString stringWithFormat:@"select * from %@ where identity = %ld",[PersistenceHelper tableName:[self class]],self.identity.longValue]];
    
    if([result count]>0)
        return [result objectAtIndex:0];
    else
        return nil;
}
 
+ (id)fetchWithIdentity:(long)identity{
    
    PersistenceManager *manager = [PersistenceManager sharedManager];
    
    NSArray *result = [manager execQuery:[self class] sql:[NSString stringWithFormat:@"select * from %@ where identity = %ld",[PersistenceHelper tableName:[self class]],identity]];
    
    if([result count]>0)
        return [result objectAtIndex:0];
    else
        return nil;
}

+(void)drop{
    PersistenceManager *manager = [PersistenceManager sharedManager];
    
    [manager drop:[self class]]; 
     

}
 
- (NSInteger)save
{
    PersistenceManager *manager = [PersistenceManager sharedManager];
    
    if (_id > 0) {
        [manager update:self];
    }else{
        [manager insert:self];
    }
    
    return _id;
}

- (NSInteger)deleteObject
{
    PersistenceManager *manager = [PersistenceManager sharedManager];
     
    [manager delete:self]; 
    
    return _id;
}
 

@end
