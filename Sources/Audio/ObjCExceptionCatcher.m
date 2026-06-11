#import "ObjCExceptionCatcher.h"

NSException *_Nullable SEQRunCatchingObjCException(void (^NS_NOESCAPE block)(void)) {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        return exception;
    }
}
