 

#import <Foundation/Foundation.h>

@interface PersistenceObject : NSObject
{
    NSInteger _id;
    NSNumber *identity;
}

@property (nonatomic, strong) NSNumber * identity;
@property (nonatomic, assign) NSInteger _id;

+ (NSArray *)transients;
+ (NSArray *)list;
+ (NSArray *)list:(NSInteger)page PageSize:(NSInteger)pageSize;
+ (NSUInteger)count;
+ (id)fetchWithIdentity:(long)identity;
+ (void)drop;
 
- (id)fetchWithIdentity;
- (NSInteger)save;
- (NSInteger)deleteObject;

@end
