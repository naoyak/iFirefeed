//
//  FirefeedAuth.m
//  iFirefeed
//
//  Created by Greg Soltis on 4/8/13.
//  Copyright (c) 2013 Firebase. All rights reserved.
//

#import "FirefeedAuth.h"


typedef void (^ffbt_void_nserror_user)(NSError* error, FAUser* user);
typedef void (^ffbt_void_void)(void);

// This class manages multiple concurrent auth requests (login, logout, status) against the same Firebase
@interface FirefeedAuthData : NSObject {
    NSMutableDictionary* _blocks;
    Firebase* _ref;
    long _luid;
    FAUser* _user;
    FirebaseSimpleLogin* _authClient;
    FirebaseHandle _authHandle;
}

- (id) initWithRef:(Firebase *)ref;
- (long) checkAuthStatus:(ffbt_void_nserror_user)block;
- (void) loginToAppWithId:(NSString *)appId;
- (void) logout;

@end

@implementation FirefeedAuthData

- (id) initWithRef:(Firebase *)ref {
    self = [super init];
    if (self) {
        // Start at 1 so it works with if (luid) {...}
        _luid = 1;
        _ref = ref;
        _user = nil;
        // Keep an eye on what Firebase says our authentication status is
        _authHandle = [[_ref childByAppendingPath:@".info/authenticated"] observeEventType:FEventTypeValue withBlock:^(FDataSnapshot *snapshot) {

            if (![(NSNumber *)snapshot.value boolValue] && _user != nil) {
                [self onAuthStatusError:nil user:nil];
            }
        }];
        _blocks = [[NSMutableDictionary alloc] init];
#ifdef _FB_DEBUG
        SEL hiddenInit = NSSelectorFromString(@"initWithRef:andApiHost:");
        _authClient = [[FirebaseSimpleLogin alloc] performSelector:hiddenInit withObject:_ref withObject:@"http://localhost:12000"];
#else
        _authClient = [[FirebaseSimpleLogin alloc] initWithRef:_ref];
#endif
    }
    return self;
}

- (void) dealloc {
    if (_authHandle != NSNotFound) {
        // Stop watching the authenticated endpoint so we don't leak memory
        [[_ref childByAppendingPath:@".info/authenticated"] removeObserverWithHandle:_authHandle];
    }
}

- (void) loginToAppWithId:(NSString *)appId {
    [_authClient loginToFacebookAppWithId:appId permissions:nil audience:nil withCompletionBlock:^(NSError *error, FAUser *user) {

        [self onAuthStatusError:error user:user];
        if (user) {
            // Populate the search indices if we got a user
            [self populateSearchIndicesForUser:user];
        }
    }];
}

- (void) populateSearchIndicesForUser:(FAUser *)user {
    // For each user, we list them in the search index twice. Once by first name and once by last name. We include the id at the end to guarantee uniqueness
    Firebase* firstNameRef = [_ref.root childByAppendingPath:@"search/firstName"];
    Firebase* lastNameRef = [_ref.root childByAppendingPath:@"search/lastName"];

    NSString* firstName = [user.thirdPartyUserData objectForKey:@"first_name"];
    NSString* lastName = [user.thirdPartyUserData objectForKey:@"last_name"];
    NSString* firstNameKey = [[NSString stringWithFormat:@"%@_%@_%@", firstName, lastName, user.userId] lowercaseString];
    NSString* lastNameKey = [[NSString stringWithFormat:@"%@_%@_%@", lastName, firstName, user.userId] lowercaseString];

    [[firstNameRef childByAppendingPath:firstNameKey] setValue:user.userId];
    [[lastNameRef childByAppendingPath:lastNameKey] setValue:user.userId];
}

- (void) logout {
    // Pass through to FirebaseSimpleAuth
    [_authClient logout];
}

// Assumes block is already on the heap
- (long) checkAuthStatus:(ffbt_void_nserror_user)block {
    long handle = _luid++;
    NSNumber* luid = [NSNumber numberWithLong:handle];

    [_blocks setObject:block forKey:luid];
    if (_user) {
        // we already have a user logged in
        // force async to be consistent
        ffbt_void_void cb = ^{
            block(nil, _user);
        };
        [self performSelector:@selector(executeCallback:) withObject:[cb copy] afterDelay:0];
    } else if (_blocks.count == 1) {
        // This is the first block for this firebase, kick off the login process
        [_authClient checkAuthStatusWithBlock:^(NSError *error, FAUser *user) {
            [self onAuthStatusError:error user:user];
        }];
    }
    return handle;
}

- (void) stopWatchingAuthStatus:(long)handle {
    NSNumber* luid = [NSNumber numberWithLong:handle];

    [_blocks removeObjectForKey:luid];
}

- (void) onAuthStatusError:(NSError *)error user:(FAUser *)user {
    if (user) {
        _user = user;
    } else {
        _user = nil;
    }
    
    for (NSNumber* handle in _blocks) {
        // tell everyone who's listening
        ffbt_void_nserror_user block = [_blocks objectForKey:handle];
        block(error, user);
    }
}

// Used w/ performSelector. Basically a hack to execute a block asynchronously
- (void) executeCallback:(ffbt_void_void)callback {
    callback();
}

@end

@interface FirefeedAuth ()

@property (strong, nonatomic) NSMutableDictionary* firebases;

@end

@implementation FirefeedAuth

+ (FirefeedAuth *) singleton {
    // We use a singleton here so that we only have one FirebaseSimpleLogin instance
    static dispatch_once_t pred;
    static FirefeedAuth* theSingleton;
    dispatch_once(&pred, ^{
        theSingleton = [[FirefeedAuth alloc] init];
    });
    return theSingleton;
}

// Pass-through methods to the singleton
+ (long) watchAuthForRef:(Firebase *)ref withBlock:(void (^)(NSError *, FAUser *))block {
    return [[self singleton] checkAuthForRef:ref withBlock:block];
}

+ (void) stopWatchingAuthForRef:(Firebase *)ref withHandle:(long)handle {
    [[self singleton] stopWatchingAuthForRef:ref withHandle:handle];
}

+ (void) loginRef:(Firebase *)ref toFacebookAppWithId:(NSString *)appId {
    [[self singleton] loginRef:ref toFacebookAppWithId:appId];
}

+ (void) logoutRef:(Firebase *)ref {
    [[self singleton] logoutRef:ref];
}

- (id) init {
    self = [super init];
    if (self) {
        self.firebases = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void) loginRef:(Firebase *)ref toFacebookAppWithId:(NSString *)appId {

    NSString* firebaseId = ref.root.description;

    // Pass to the FirefeedAuthData object, which manages multiple auth requests against the same Firebase
    FirefeedAuthData* authData = [self.firebases objectForKey:firebaseId];
    if (!authData) {
        authData = [[FirefeedAuthData alloc] initWithRef:ref.root];
        [self.firebases setObject:authData forKey:firebaseId];
    }
    [authData loginToAppWithId:appId];
}

- (void) logoutRef:(Firebase *)ref {
    NSString* firebaseId = ref.root.description;

    // Pass to the FirefeedAuthData object, which manages multiple auth requests against the same Firebase
    FirefeedAuthData* authData = [self.firebases objectForKey:firebaseId];
    if (!authData) {
        authData = [[FirefeedAuthData alloc] initWithRef:ref.root];
        [self.firebases setObject:authData forKey:firebaseId];
    }

    [authData logout];
}


- (void) stopWatchingAuthForRef:(Firebase *)ref withHandle:(long)handle {
    NSString* firebaseId = ref.root.description;

    // Pass to the FirefeedAuthData object, which manages multiple auth requests against the same Firebase
    FirefeedAuthData* authData = [self.firebases objectForKey:firebaseId];
    if (authData) {
        [authData stopWatchingAuthStatus:handle];
    }
}

- (long) checkAuthForRef:(Firebase *)ref withBlock:(ffbt_void_nserror_user)block {
    ffbt_void_nserror_user userBlock = [block copy];
    NSString* firebaseId = ref.root.description;

    // Pass to the FirefeedAuthData object, which manages multiple auth requests against the same Firebase
    FirefeedAuthData* authData = [self.firebases objectForKey:firebaseId];
    if (!authData) {
        authData = [[FirefeedAuthData alloc] initWithRef:ref.root];
        [self.firebases setObject:authData forKey:firebaseId];
    }

    return [authData checkAuthStatus:userBlock];
}

@end
