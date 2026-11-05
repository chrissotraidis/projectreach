/* Saved-player name lookup for the Service Record nameplate. Synthetic temp
 * profiles only; never reads installed saves or starts the engine. */
#import <Foundation/Foundation.h>
#import "HPHaloProgressStore.h"
#include <unistd.h>
uintptr_t xg_base; /* never starts the engine */
static void Write(NSString *root,NSString *folder,NSString *name,BOOL terminate){
    NSString *dir=[root stringByAppendingPathComponent:[@"u/UDATA" stringByAppendingPathComponent:folder]];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableData *data=[NSMutableData dataWithLength:512];uint8_t *b=data.mutableBytes;
    for(NSUInteger i=0;i<name.length&&i<12;i++){unichar c=[name characterAtIndex:i];b[i*2]=c&0xff;b[i*2+1]=c>>8;}
    if(!terminate)for(NSUInteger i=name.length;i<12;i++){b[i*2]='x';b[i*2+1]=0;}
    [data writeToFile:[dir stringByAppendingPathComponent:@"blam.sav"] atomically:YES];
}
int main(void){@autoreleasepool{
    NSString *root=[@(getenv("HALOPAD_TEST_RESULTS")) stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    Write(root,@"122AAC4D32E4",@"TestPlayer",YES);
    Write(root,@"AAAAAAAAAAAA",@"Elevenchars",YES);
    Write(root,@"BBBBBBBBBBBB",@"abc",NO);
    Write(root,@"CCCCCCCCCCCC",@"bad\x01name",YES);
    Write(root,@"DDDDDDDDDDDD",@"Spartan",YES);
    NSString *link=[root stringByAppendingPathComponent:@"u/UDATA/EEEEEEEEEEEE"];
    [NSFileManager.defaultManager createDirectoryAtPath:link withIntermediateDirectories:YES attributes:nil error:nil];
    symlink([[root stringByAppendingPathComponent:@"u/UDATA/DDDDDDDDDDDD/blam.sav"] fileSystemRepresentation],[[link stringByAppendingPathComponent:@"blam.sav"] fileSystemRepresentation]);
    HPHaloProgressConfigure(root);
    int failures=0;
    #define EXPECT(cond,label) do{ if(!(cond)){failures++;printf("FAIL %s\n",label);} else printf("PASS %s\n",label);}while(0)
    EXPECT([HPHaloProgressPlayerName(@"U:\\UDATA\\122AAC4D32E4") isEqualToString:@"TestPlayer"],"reads the saved player's name");
    EXPECT([HPHaloProgressPlayerName(@"u:/udata/122aac4d32e4/") isEqualToString:@"TestPlayer"],"accepts the same validated path forms as XP");
    EXPECT([HPHaloProgressPlayerName(@"U:\\UDATA\\AAAAAAAAAAAA") isEqualToString:@"Elevenchars"],"keeps an 11-character name");
    EXPECT(HPHaloProgressPlayerName(@"U:\\UDATA\\BBBBBBBBBBBB")==nil,"rejects an unterminated name field");
    EXPECT(HPHaloProgressPlayerName(@"U:\\UDATA\\CCCCCCCCCCCC")==nil,"rejects control characters");
    EXPECT(HPHaloProgressPlayerName(@"U:\\UDATA\\EEEEEEEEEEEE")==nil,"refuses a symlinked profile file");
    EXPECT(HPHaloProgressPlayerName(@"U:\\UDATA\\FFFFFFFFFFFF")==nil,"missing profile returns nil");
    EXPECT(HPHaloProgressPlayerName(@"U:\\UDATA\\..\\..\\etc")==nil,"rejects traversal paths");
    EXPECT(HPHaloProgressPlayerName(@"")==nil,"rejects empty path");
    [NSFileManager.defaultManager removeItemAtPath:root error:nil];
    printf("%s\n",failures?"FAILED":"ALL PASSED");return failures?1:0;
}}
