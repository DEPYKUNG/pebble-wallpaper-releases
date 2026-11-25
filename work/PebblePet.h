#import <AppKit/AppKit.h>
#import "PebblePetEffects.h"

@interface PebblePetController : NSObject
@property (nonatomic, readonly) NSPanel *panel;
@property (nonatomic, readonly) BOOL dragging;
@property (nonatomic, readonly) BOOL interacting;
@property (nonatomic) BOOL roaming;
@property (nonatomic) BOOL skippingEnabled,speechEnabled,casualSpeech;
@property (nonatomic) NSInteger skipLimit;
@property (nonatomic, readonly) BOOL skipping;
@property (nonatomic) BOOL skippedWithCurrentStone;
@property (nonatomic, readonly) PebblePetEffects *effects;
@property (nonatomic) NSInteger sizeIndex;
@property (nonatomic, copy) void (^syncStone)(void);
@property (nonatomic, copy) void (^collectStone)(void);
@property (nonatomic, copy) void (^earnBadge)(NSString *badge);
@property (nonatomic, copy) void (^dismissPet)(void);
@property (nonatomic, copy) void (^openSettings)(void);
@property (nonatomic, copy) void (^interactionEnded)(void);
@property (nonatomic, readonly) NSImage *stoneImage;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (BOOL)setStonePNG:(NSData *)data;
- (void)setSuspended:(BOOL)suspended;
- (void)refreshScreens;
- (void)summon:(id)sender;
- (void)greet:(id)sender;
- (void)skip:(id)sender;
- (void)say:(id)sender;
- (BOOL)showMessage:(NSString *)message priority:(PebblePetMessagePriority)priority duration:(NSTimeInterval)duration;
- (BOOL)showUpdateWithAction:(void (^)(void))action;
- (void)invalidate;
// Pointer samples are explicit so the real gesture path can be regression-tested.
- (void)beginDragAtPoint:(NSPoint)point time:(NSTimeInterval)time;
- (void)dragToPoint:(NSPoint)point time:(NSTimeInterval)time;
- (void)endDragAtTime:(NSTimeInterval)time;
- (void)savePlacement;
- (BOOL)containsStoneAtScreenPoint:(NSPoint)point;
@end
