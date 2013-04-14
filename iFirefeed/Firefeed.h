//
//  Firefeed.h
//  iFirefeed
//
//  Created by Greg Soltis on 4/2/13.
//  Copyright (c) 2013 Firebase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <FirebaseAuthClient/FirebaseAuthClient.h>
#import "FirefeedUser.h"
#import "FirefeedSpark.h"

@protocol FirefeedDelegate;

//#define _FB_DEBUG

#ifdef _FB_DEBUG
// debug
#define kFacebookAppId @"321090668014055"
#define kFirebaseRoot @"http://firefeed.fblocal.com:9000"

#else

// Public
#define kFacebookAppId @"104907529680402"
#define kFirebaseRoot @"http://firefeed.firebaseio.com"

#endif

@interface Firefeed : NSObject

+ (void) logDiagnostics;

- (id) initWithUrl:(NSString *)rootUrl;
- (void) login;
- (void) logout;
- (NSString *) observeLatestSparks;
- (NSString *) observeLoggedInUserTimeline;
- (NSString *) observeSparksForUser:(NSString *)userId;
- (void) stopObservingTimeline:(NSString *)timeline;
- (void) postSpark:(NSString *)text completionBlock:(void (^)(NSError* err))block;
- (void) observeUserInfo:(NSString *)userId;
- (void) observeFollowersForUser:(NSString *)userId;
- (void) observeFolloweesForUser:(NSString *)userId;
- (BOOL) userIsLoggedInUser:(NSString *)userId;
- (void) startFollowingUser:(NSString *)userId;
- (void) stopFollowingUser:(NSString *)userId;
- (void) saveUser:(FirefeedUser *)user;
- (void) cleanup;

// Debugging
- (void) logListens;
//- (void) cleanupUsers;

@property (weak, nonatomic) id <FirefeedDelegate> delegate;

@end

@protocol FirefeedDelegate <NSObject>

- (void) loginStateDidChange:(FirefeedUser *)user;
- (void) spark:(FirefeedSpark *)spark wasAddedToTimeline:(NSString *)timeline;
- (void) spark:(FirefeedSpark *)spark wasOverflowedFromTimeline:(NSString *)timeline;
- (void) follower:(FirefeedUser *)follower startedFollowing:(FirefeedUser *)followee;
- (void) follower:(FirefeedUser *)follower stoppedFollowing:(FirefeedUser *)followee;
- (void) userDidUpdate:(FirefeedUser *)user;

@end