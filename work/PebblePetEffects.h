#import <AppKit/AppKit.h>

typedef NS_ENUM(NSInteger, PebblePetMessagePriority) {
    PebblePetMessageAmbient=0, PebblePetMessageInteraction=1, PebblePetMessageReminder=2
};

// Main-thread presentation API for later reminder producers. No scheduler or task data lives here.
@interface PebblePetEffects : NSObject
@property (nonatomic) BOOL speechEnabled;
@property (nonatomic, readonly) NSPanel *bubblePanel;
@property (nonatomic, readonly) NSString *message;
@property (nonatomic, readonly) NSUInteger rippleCount;
- (BOOL)showMessage:(NSString *)message priority:(PebblePetMessagePriority)priority duration:(NSTimeInterval)duration;
- (BOOL)showMessage:(NSString *)message episodeURL:(NSURL *)url priority:(PebblePetMessagePriority)priority duration:(NSTimeInterval)duration;
- (BOOL)showUpdateWithAction:(void (^)(void))action;
- (BOOL)showFocusChoice:(NSString *)message restart:(void (^)(void))restart rest:(void (^)(void))rest;
- (void)addRippleAt:(NSPoint)point color:(NSColor *)color;
- (void)updateAtTime:(NSTimeInterval)time anchor:(NSRect)anchor visible:(NSRect)visible;
- (void)clear;
@end
