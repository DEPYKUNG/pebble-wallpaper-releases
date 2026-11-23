#import <AppKit/AppKit.h>
@interface PebbleChangelogView : NSView
- (instancetype)initWithEntries:(NSArray *)entries currentVersion:(NSString *)version viewAllButton:(NSButton *)button;
@end
