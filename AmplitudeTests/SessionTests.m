//
//  SessionTests.m
//  SessionTests
//
//  Created by Curtis on 9/24/14.
//  Copyright (c) 2014 Amplitude. All rights reserved.
//
//  NOTE: Having a lot of OCMock partialMockObjects causes tests to be flakey.
//        Combined a lot of tests into one large test so they share a single
//        mockAmplitude object instead creating lots of separate ones.
//        This seems to have fixed the flakiness issue.
//

#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>
#import <OCMock/OCMock.h>
#import "Amplitude.h"
#import "Amplitude+Test.h"
#import "BaseTestCase.h"
#import "AMPUtils.h"

@interface SessionTests : BaseTestCase

@end

@implementation SessionTests { }

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)testSessionAutoStartedBackground {
    // mock application state
    id mockApplication = [OCMockObject niceMockForClass:[UIApplication class]];
    [[[mockApplication stub] andReturn:mockApplication] sharedApplication];
    OCMStub([mockApplication applicationState]).andReturn(UIApplicationStateBackground);

    // mock amplitude object and verify enterForeground not called
    id mockAmplitude = [OCMockObject partialMockForObject:self.amplitude];
    [[mockAmplitude reject] enterForeground];
    [mockAmplitude initializeApiKey:apiKey];
    [mockAmplitude flushQueueWithQueue:[mockAmplitude initializerQueue]];
    [mockAmplitude flushQueue];
    [mockAmplitude verify];
    XCTAssertEqual([mockAmplitude queuedEventCount], 0);
}

- (void)testSessionAutoStartedInactive {
    id mockApplication = [OCMockObject niceMockForClass:[UIApplication class]];
    [[[mockApplication stub] andReturn:mockApplication] sharedApplication];
    OCMStub([mockApplication applicationState]).andReturn(UIApplicationStateInactive);

    id mockAmplitude = [OCMockObject partialMockForObject:self.amplitude];
    [[mockAmplitude expect] enterForeground];
    [mockAmplitude initializeApiKey:apiKey];
    [mockAmplitude flushQueueWithQueue:[mockAmplitude initializerQueue]];
    [mockAmplitude flushQueue];
    [mockAmplitude verify];
    XCTAssertEqual([mockAmplitude queuedEventCount], 0);
}

- (void)testSessionHandling {

    // start new session on initializeApiKey
    id mockAmplitude = [OCMockObject partialMockForObject:self.amplitude];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:1000];
    [[[mockAmplitude expect] andReturnValue:OCMOCK_VALUE(date)] currentTime];

    [mockAmplitude initializeApiKey:apiKey userId:nil];
    [mockAmplitude flushQueueWithQueue:[mockAmplitude initializerQueue]];
    [mockAmplitude flushQueue];
    XCTAssertEqual([mockAmplitude queuedEventCount], 0);
    XCTAssertEqual([mockAmplitude sessionId], 1000000);

    // also test getSessionId
    XCTAssertEqual([mockAmplitude getSessionId], 1000000);

    // A new session should start on UIApplicationWillEnterForeground after minTimeBetweenSessionsMillis
    [[[mockAmplitude expect] andReturnValue:OCMOCK_VALUE(date)] currentTime];
    [mockAmplitude enterBackground]; // simulate app entering background
    [mockAmplitude flushQueue];
    XCTAssertEqual([mockAmplitude sessionId], 1000000);

    NSDate *date2 = [NSDate dateWithTimeIntervalSince1970:1000 + (self.amplitude.minTimeBetweenSessionsMillis / 1000)];
    [[[mockAmplitude expect] andReturnValue:OCMOCK_VALUE(date2)] currentTime];
    [mockAmplitude enterForeground]; // simulate app entering foreground
    [mockAmplitude flushQueue];

    XCTAssertEqual([mockAmplitude queuedEventCount], 0);
    XCTAssertEqual([mockAmplitude sessionId], 1000000 + self.amplitude.minTimeBetweenSessionsMillis);


    // An event should continue the session in the foreground after minTimeBetweenSessionsMillis + 1 seconds
    NSDate *date3 = [NSDate dateWithTimeIntervalSince1970:1000 + (self.amplitude.minTimeBetweenSessionsMillis / 1000) + 1];
    [[[mockAmplitude expect] andReturnValue:OCMOCK_VALUE(date3)] currentTime];
    [mockAmplitude logEvent:@"continue_session"];
    [mockAmplitude flushQueue];

    XCTAssertEqual([[mockAmplitude lastEventTime] longLongValue], 1001000 + self.amplitude.minTimeBetweenSessionsMillis);
    XCTAssertEqual([mockAmplitude queuedEventCount], 1);
    XCTAssertEqual([mockAmplitude sessionId], 1000000 + self.amplitude.minTimeBetweenSessionsMillis);


    // session should continue on UIApplicationWillEnterForeground after minTimeBetweenSessionsMillis - 1 second
    NSDate *date4 = [NSDate dateWithTimeIntervalSince1970:2000];
    [[[mockAmplitude expect] andReturnValue:OCMOCK_VALUE(date4)] currentTime];
    [mockAmplitude enterBackground]; // simulate app entering background

    NSDate *date5 = [NSDate dateWithTimeIntervalSince1970:2000 + (self.amplitude.minTimeBetweenSessionsMillis / 1000) - 1];
    [[[mockAmplitude expect] andReturnValue:OCMOCK_VALUE(date5)] currentTime];
    [mockAmplitude enterForeground]; // simulate app entering foreground
    [mockAmplitude flushQueue];

    XCTAssertEqual([mockAmplitude queuedEventCount], 1);
    XCTAssertEqual([mockAmplitude sessionId], 1000000 + self.amplitude.minTimeBetweenSessionsMillis);


   // test out of session event
    NSDate *date6 = [NSDate dateWithTimeIntervalSince1970:3000];
    [[[mockAmplitude expect] andReturnValue:OCMOCK_VALUE(date6)] currentTime];
    [mockAmplitude logEvent:@"No Session" withEventProperties:nil outOfSession:NO];
    [mockAmplitude flushQueue];
    XCTAssert([[mockAmplitude getLastEvent][@"session_id"]
               isEqualToNumber:[NSNumber numberWithLongLong:1000000 + self.amplitude.minTimeBetweenSessionsMillis]]);

    NSDate *date7 = [NSDate dateWithTimeIntervalSince1970:3001];
    [[[mockAmplitude expect] andReturnValue:OCMOCK_VALUE(date7)] currentTime];
    // An out of session event should have session_id = -1
    [mockAmplitude logEvent:@"No Session" withEventProperties:nil outOfSession:YES];
    [mockAmplitude flushQueue];
    XCTAssert([[mockAmplitude getLastEvent][@"session_id"]
               isEqualToNumber:[NSNumber numberWithLongLong:-1]]);

    // An out of session event should not continue the session
    XCTAssertEqual([[mockAmplitude lastEventTime] longLongValue], 3000000); // event time of first no session
}

- (void)testEnterBackgroundDoesNotTrackEvent {
    [self.amplitude initializeApiKey:apiKey userId:nil];
    [self.amplitude flushQueueWithQueue:self.amplitude.initializerQueue];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil userInfo:nil];

    [self.amplitude flushQueue];
    XCTAssertEqual([self.amplitude queuedEventCount], 0);
}

- (void)testTrackSessionEvents {
    AMPDatabaseHelper *dbHelper = [AMPDatabaseHelper getDatabaseHelper];

    id mockAmplitude = [OCMockObject partialMockForObject:self.amplitude];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:1000];
    [[[mockAmplitude expect] andReturnValue:OCMOCK_VALUE(date)] currentTime];
    [mockAmplitude setTrackingSessionEvents:YES];

    [mockAmplitude initializeApiKey:apiKey userId:nil];
    [mockAmplitude flushQueueWithQueue:[mockAmplitude initializerQueue]];
    [mockAmplitude flushQueue];

    XCTAssertEqual([mockAmplitude queuedEventCount], 1);
    XCTAssertEqual([[mockAmplitude getLastEvent][@"session_id"] longLongValue], 1000000);
    XCTAssertEqualObjects([mockAmplitude getLastEvent][@"event_type"], kAMPSessionStartEvent);


    // test end session with tracking session events
    [[[mockAmplitude expect] andReturnValue:OCMOCK_VALUE(date)] currentTime];
    [mockAmplitude enterBackground]; // simulate app entering background

    NSDate *date2 = [NSDate dateWithTimeIntervalSince1970:1000 + (self.amplitude.minTimeBetweenSessionsMillis / 1000)];
    [[[mockAmplitude expect] andReturnValue:OCMOCK_VALUE(date2)] currentTime];
    [mockAmplitude enterForeground]; // simulate app entering foreground
    [mockAmplitude flushQueue];
    XCTAssertEqual([mockAmplitude queuedEventCount], 3);

    long long expectedSessionId = 1000000 + self.amplitude.minTimeBetweenSessionsMillis;
    XCTAssertEqual([mockAmplitude sessionId], expectedSessionId);

    XCTAssertEqual([[self.amplitude getEvent:1][@"session_id"] longLongValue], 1000000);
    XCTAssertEqualObjects([self.amplitude getEvent:1][@"event_type"], kAMPSessionEndEvent);
    XCTAssertEqual([[self.amplitude getEvent:1][@"timestamp"] longLongValue], 1000000);

    XCTAssertEqual([[self.amplitude getLastEvent][@"session_id"] longLongValue], expectedSessionId);
    XCTAssertEqualObjects([self.amplitude getLastEvent][@"event_type"], kAMPSessionStartEvent);

    // test in session identify with app in background
    [[[mockAmplitude expect] andReturnValue:OCMOCK_VALUE(date2)] currentTime];
    [mockAmplitude enterBackground]; // simulate app entering background

    NSDate *date3 = [NSDate dateWithTimeIntervalSince1970:1000 + 2 * self.amplitude.minTimeBetweenSessionsMillis];
    [[[mockAmplitude expect] andReturnValue:OCMOCK_VALUE(date3)] currentTime];
    AMPIdentify *identify = [[AMPIdentify identify] set:@"key" value:@"value"];
    [mockAmplitude identify:identify outOfSession:NO];
    [mockAmplitude flushQueue];
    XCTAssertEqual([mockAmplitude queuedEventCount], 5); // triggers session events

    // test out of session identify with app in background
    NSDate *date4 = [NSDate dateWithTimeIntervalSince1970:1000 + 3 * self.amplitude.minTimeBetweenSessionsMillis];
    [[[mockAmplitude expect] andReturnValue:OCMOCK_VALUE(date4)] currentTime];
    [mockAmplitude identify:identify outOfSession:YES];
    [mockAmplitude flushQueue];
    XCTAssertEqual([mockAmplitude queuedEventCount], 5); // does not trigger session events

    // test new end session logic -> go to background
    NSDate *date5 = [NSDate dateWithTimeIntervalSince1970:1000 + 4 * self.amplitude.minTimeBetweenSessionsMillis];
    [[[mockAmplitude expect] andReturnValue:OCMOCK_VALUE(date5)] currentTime];
    [mockAmplitude enterBackground]; // simulate app entering background
    [mockAmplitude flushQueue];
    XCTAssertEqual([mockAmplitude queuedEventCount], 5); // no actual events logged

    // verify end session event is added to key value table
    NSString *endSessionEventString = [dbHelper getValue:kAMPSessionEndEvent];
    XCTAssertFalse([AMPUtils isEmptyString:endSessionEventString]);
    NSDictionary *endSessionEvent = [AMPUtils deserializeEventString:endSessionEventString];
    XCTAssertNotNil(endSessionEvent);
    NSNumber *endSessionTimestamp = [endSessionEvent objectForKey:@"timestamp"];
    NSNumber *expectedTimestamp = [NSNumber numberWithLongLong:[date5 timeIntervalSince1970] * 1000];
    XCTAssertEqualObjects(expectedTimestamp, endSessionTimestamp);

    // verify that the end session event sent is loaded from key value table
    // we can modify the value in the database and verify the modified event is the one that is sent
    // adding a value for version_name
    endSessionEventString = @"{\"uuid\":\"CC83932C-7520-4AAD-BC95-8E59D30057D6\",\"device_manufacturer\":\"Apple\",\"library\":{\"name\":\"amplitude-ios\",\"version\":\"3.11.1\"},\"event_type\":\"session_end\",\"os_name\":\"ios\",\"sequence_number\":10,\"timestamp\":1201000000,\"event_properties\":{},\"api_properties\":{\"special\":\"session_end\",\"ios_idfv\":\"AFD750D7-1A23-44AB-A091-673A6229647A\"},\"groups\":{},\"user_properties\":{},\"platform\":\"iOS\",\"language\":\"English\",\"device_id\":\"AFD750D7-1A23-44AB-A091-673A6229647A\",\"os_version\":\"10.1\",\"session_id\":601000000,\"device_model\":\"Simulator\",\"country\":\"United States\",\"version_name\":\"test_version\"}";
    [dbHelper insertOrReplaceKeyValue:kAMPSessionEndEvent value:endSessionEventString];

    // force app to foreground and verify new session logic
    NSDate *date6 = [NSDate dateWithTimeIntervalSince1970:1000 + 5 * self.amplitude.minTimeBetweenSessionsMillis];
    [[[mockAmplitude expect] andReturnValue:OCMOCK_VALUE(date6)] currentTime];
    [mockAmplitude enterForeground];
    [mockAmplitude flushQueue];
    XCTAssertEqual([mockAmplitude queuedEventCount], 7); // end and start session events logged

    NSArray *events = [dbHelper getEvents:-1 limit:-1];
    XCTAssertEqual([events count], 7);
    endSessionEvent = [events objectAtIndex:5];
    XCTAssertEqualObjects([endSessionEvent objectForKey:@"event_type"], kAMPSessionEndEvent);
    XCTAssertEqualObjects([endSessionEvent objectForKey:@"timestamp"], expectedTimestamp);
    XCTAssertEqualObjects([endSessionEvent objectForKey:@"version_name"], @"test_version");
    XCTAssertNil([dbHelper getValue:kAMPSessionEndEvent]);

    // the start session event should be missing the version_name
    expectedTimestamp = [NSNumber numberWithLongLong:[date6 timeIntervalSince1970] * 1000];
    NSDictionary *startSessionEvent = [events objectAtIndex:6];
    XCTAssertEqualObjects([startSessionEvent objectForKey:@"event_type"], kAMPSessionStartEvent);
    XCTAssertEqualObjects([startSessionEvent objectForKey:@"timestamp"], expectedTimestamp);
    XCTAssertNil([startSessionEvent objectForKey:@"version_name"]);

    // test new session logic -> verify saved end session event is discarded if the timestamp does not match
    // the start session event logged at date6 should have updated the lastEventTime
    [[[mockAmplitude expect] andReturnValue:OCMOCK_VALUE(date6)] currentTime];
    [mockAmplitude enterBackground]; // simulate app entering background
    [mockAmplitude flushQueue];
    XCTAssertEqual([mockAmplitude queuedEventCount], 7); // no actual events logged

    // if we try to re-send our modified endSessionEventString with date5, it should discard it and log a new one
    endSessionEventString = @"{\"uuid\":\"CC83932C-7520-4AAD-BC95-8E59D30057D6\",\"device_manufacturer\":\"Apple\",\"library\":{\"name\":\"amplitude-ios\",\"version\":\"3.11.1\"},\"event_type\":\"session_end\",\"os_name\":\"ios\",\"sequence_number\":10,\"timestamp\":1201000000,\"event_properties\":{},\"api_properties\":{\"special\":\"session_end\",\"ios_idfv\":\"AFD750D7-1A23-44AB-A091-673A6229647A\"},\"groups\":{},\"user_properties\":{},\"platform\":\"iOS\",\"language\":\"English\",\"device_id\":\"AFD750D7-1A23-44AB-A091-673A6229647A\",\"os_version\":\"10.1\",\"session_id\":601000000,\"device_model\":\"Simulator\",\"country\":\"United States\",\"version_name\":\"test_version\"}";
    [dbHelper insertOrReplaceKeyValue:kAMPSessionEndEvent value:endSessionEventString];

    // force app to foreground and verify new session logic
    NSDate *date7 = [NSDate dateWithTimeIntervalSince1970:1000 + 6 * self.amplitude.minTimeBetweenSessionsMillis];
    [[[mockAmplitude expect] andReturnValue:OCMOCK_VALUE(date7)] currentTime];
    [mockAmplitude enterForeground];
    [mockAmplitude flushQueue];
    XCTAssertEqual([mockAmplitude queuedEventCount], 9); // end and start session events logged

    events = [dbHelper getEvents:-1 limit:-1];
    XCTAssertEqual([events count], 9);
    endSessionEvent = [events objectAtIndex:7];
    XCTAssertEqualObjects([endSessionEvent objectForKey:@"event_type"], kAMPSessionEndEvent);
    XCTAssertEqualObjects([endSessionEvent objectForKey:@"timestamp"], expectedTimestamp);
    XCTAssertNil([endSessionEvent objectForKey:@"version_name"]);  // should be missing the version_name since a brand new end session event is logged
    XCTAssertNil([dbHelper getValue:kAMPSessionEndEvent]);

    // the start session event should be missing the version_name
    startSessionEvent = [events objectAtIndex:8];
    XCTAssertEqualObjects([startSessionEvent objectForKey:@"event_type"], kAMPSessionStartEvent);
    XCTAssertEqualObjects([startSessionEvent objectForKey:@"timestamp"], [NSNumber numberWithLongLong:[date7 timeIntervalSince1970] * 1000]);
    XCTAssertNil([startSessionEvent objectForKey:@"version_name"]);

}

- (void)testSessionEventsOn32BitDevices {
    id mockAmplitude = [OCMockObject partialMockForObject:self.amplitude];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:21474836470];
    [[[mockAmplitude expect] andReturnValue:OCMOCK_VALUE(date)] currentTime];
    [mockAmplitude setTrackingSessionEvents:YES];

    [mockAmplitude initializeApiKey:apiKey userId:nil];
    [mockAmplitude flushQueueWithQueue:[mockAmplitude initializerQueue]];
    [mockAmplitude flushQueue];

    XCTAssertEqual([mockAmplitude queuedEventCount], 1);
    XCTAssertEqual([[mockAmplitude getLastEvent][@"session_id"] longLongValue], 21474836470000);
    XCTAssertEqualObjects([mockAmplitude getLastEvent][@"event_type"], kAMPSessionStartEvent);


    // test end session with tracking session events
    [[[mockAmplitude expect] andReturnValue:OCMOCK_VALUE(date)] currentTime];
    [mockAmplitude enterBackground]; // simulate app entering background

    NSDate *date2 = [NSDate dateWithTimeIntervalSince1970:214748364700];
    [[[mockAmplitude expect] andReturnValue:OCMOCK_VALUE(date2)] currentTime];
    [mockAmplitude enterForeground]; // simulate app entering foreground
    [self.amplitude flushQueue];
    XCTAssertEqual([mockAmplitude queuedEventCount], 3);

    XCTAssertEqual([mockAmplitude sessionId], 214748364700000);

    XCTAssertEqual([[self.amplitude getEvent:1][@"session_id"] longLongValue], 21474836470000);
    XCTAssertEqualObjects([self.amplitude getEvent:1][@"event_type"], kAMPSessionEndEvent);

    XCTAssertEqual([[self.amplitude getLastEvent][@"session_id"] longLongValue], 214748364700000);
    XCTAssertEqualObjects([self.amplitude getLastEvent][@"event_type"], kAMPSessionStartEvent);
}

- (void)testSkipSessionCheckWhenLoggingSessionEvents {
    AMPDatabaseHelper *dbHelper = [AMPDatabaseHelper getDatabaseHelper];

    NSDate *date = [NSDate dateWithTimeIntervalSince1970:1000];
    NSNumber *timestamp = [NSNumber numberWithLongLong:[date timeIntervalSince1970] * 1000];
    [dbHelper insertOrReplaceKeyLongValue:@"previous_session_id" value:timestamp];

    self.amplitude.trackingSessionEvents = YES;
    [self.amplitude initializeApiKey:apiKey userId:nil];

    [self.amplitude flushQueue];
    XCTAssertEqual([dbHelper getEventCount], 2);
    NSArray *events = [dbHelper getEvents:-1 limit:2];
    XCTAssertEqualObjects(events[0][@"event_type"], kAMPSessionEndEvent);
    XCTAssertEqualObjects(events[1][@"event_type"], kAMPSessionStartEvent);
}

@end
