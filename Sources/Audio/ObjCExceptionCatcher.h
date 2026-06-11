#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block`, catching any NSException it throws. Returns the exception
/// (or nil on success) so Swift callers can survive Objective-C exceptions
/// from frameworks like AVFAudio, which Swift cannot catch natively.
NSException *_Nullable SEQRunCatchingObjCException(void (^NS_NOESCAPE block)(void));

NS_ASSUME_NONNULL_END
