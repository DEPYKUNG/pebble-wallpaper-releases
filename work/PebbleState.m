#import "PebbleState.h"
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>

static BOOL NumberInRange(id value, double lower, double upper, BOOL integer) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NO;
    double number = [value doubleValue];
    return isfinite(number) && number >= lower && number <= upper && (!integer || floor(number) == number);
}

NSDictionary *PebbleNormalizeStone(id value, NSArray<NSString *> *textures) {
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *stone = value;
    if (stone[@"schemaVersion"] && !NumberInRange(stone[@"schemaVersion"], 1, 1, YES)) return nil;
    if (!NumberInRange(stone[@"seed"], 0, 999999, YES) ||
        ![stone[@"texture"] isKindOfClass:NSString.class] || ![textures containsObject:stone[@"texture"]] ||
        ![stone[@"faces"] isKindOfClass:NSString.class] || ![@[@"", @"on", @"off"] containsObject:stone[@"faces"]]) return nil;
    NSArray *colors = stone[@"colors"];
    if (![colors isKindOfClass:NSArray.class] || colors.count != 3) return nil;
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    for (id color in colors) {
        if (![color isKindOfClass:NSString.class] || [color length] != 7 || ![color hasPrefix:@"#"] ||
            [[color substringFromIndex:1] rangeOfCharacterFromSet:hex.invertedSet].location != NSNotFound) return nil;
    }
    id yaw = stone[@"yaw"] ?: @0, pitch = stone[@"pitch"] ?: @(-.12);
    if (!NumberInRange(yaw, -2 * M_PI, 2 * M_PI, NO) || !NumberInRange(pitch, -M_PI_2, M_PI_2, NO)) return nil;
    return @{@"schemaVersion":@1, @"seed":stone[@"seed"], @"texture":stone[@"texture"],
        @"colors":colors, @"faces":stone[@"faces"], @"yaw":yaw, @"pitch":pitch};
}

NSDictionary *PebbleNormalizeHistory(id value, NSArray<NSString *> *textures) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (![value isKindOfClass:NSDictionary.class]) return result;
    for (NSString *key in @[@"current", @"previous"]) {
        NSDictionary *stone = PebbleNormalizeStone(value[key], textures);
        if (stone) result[key] = stone;
    }
    return result;
}

NSDictionary *PebbleNormalizeHistories(id value, NSArray<NSString *> *textures) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (![value isKindOfClass:NSDictionary.class]) return result;
    NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet;
    for (id key in value) {
        if (![key isKindOfClass:NSString.class] || ![key length] || [key rangeOfCharacterFromSet:digits.invertedSet].location != NSNotFound) continue;
        NSDictionary *history = PebbleNormalizeHistory(value[key], textures);
        if (history.count) result[key] = history;
    }
    return result;
}

NSDictionary *PebbleStoneIdentity(NSDictionary *stone) {
    return [stone dictionaryWithValuesForKeys:@[@"seed", @"texture", @"colors", @"faces"]];
}

NSArray *PebbleNormalizeFavorites(id value, NSArray<NSString *> *textures) {
    NSMutableArray *result = [NSMutableArray array];
    NSMutableSet *identities = [NSMutableSet set];
    if (![value isKindOfClass:NSArray.class]) return result;
    for (id candidate in value) {
        NSDictionary *stone = PebbleNormalizeStone(candidate, textures);
        if (!stone) continue;
        NSDictionary *identity = PebbleStoneIdentity(stone);
        if ([identities containsObject:identity]) continue;
        NSMutableDictionary *entry = [stone mutableCopy];
        if (NumberInRange(candidate[@"collectedAt"], 0, 253402300799, NO))
            entry[@"collectedAt"] = candidate[@"collectedAt"];
        if ([@[@"wallpaper", @"rethrow", @"pet", @"skip"] containsObject:candidate[@"collectionSource"] ?: @""])
            entry[@"collectionSource"] = candidate[@"collectionSource"];
        [identities addObject:identity];
        [result addObject:entry];
    }
    return result;
}

NSArray<NSNumber *> *PebbleTargetDisplays(NSArray<NSNumber *> *connected, NSNumber *selected, BOOL allWhenUnselected) {
    if (selected) return [connected containsObject:selected] ? @[selected] : @[];
    return allWhenUnselected ? connected : (connected.count ? @[connected.firstObject] : @[]);
}
