//
//  FLEXNetworkTransaction.m
//  Flipboard
//
//  Created by Ryan Olson on 2/8/15.
//  Copyright (c) 2020 FLEX Team. All rights reserved.
//

#import "FLEXNetworkTransaction.h"
#import "FLEXResources.h"
#import "FLEXUtility.h"

@interface FLEXNetworkTransaction () {
    @protected
    
    NSString *_primaryDescription;
    NSString *_secondaryDescription;
    NSString *_tertiaryDescription;
}

@end

@implementation FLEXNetworkTransaction

+ (NSString *)readableStringFromTransactionState:(FLEXNetworkTransactionState)state {
    NSString *readableString = nil;
    switch (state) {
        case FLEXNetworkTransactionStateUnstarted:
            readableString = @"Unstarted";
            break;
            
        case FLEXNetworkTransactionStateAwaitingResponse:
            readableString = @"Awaiting Response";
            break;
            
        case FLEXNetworkTransactionStateReceivingData:
            readableString = @"Receiving Data";
            break;
            
        case FLEXNetworkTransactionStateFinished:
            readableString = @"Finished";
            break;
            
        case FLEXNetworkTransactionStateFailed:
            readableString = @"Failed";
            break;
    }
    return readableString;
}

+ (instancetype)withStartTime:(NSDate *)startTime {
    FLEXNetworkTransaction *transaction = [self new];
    transaction->_startTime = startTime;
    return transaction;
}

- (NSString *)timestampStringFromRequestDate:(NSDate *)date {
    static NSDateFormatter *dateFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [NSDateFormatter new];
        dateFormatter.dateFormat = @"HH:mm:ss";
    });
    
    return [dateFormatter stringFromDate:date];
}

- (void)setState:(FLEXNetworkTransactionState)transactionState {
    _state = transactionState;
    // Reset bottom description
    _tertiaryDescription = nil;
}

- (BOOL)displayAsError {
    return _error != nil;
}

- (NSString *)copyString {
    return nil;
}

- (BOOL)matchesQuery:(NSString *)filterString {
    return NO;
}

@end


@interface FLEXURLTransaction ()

@end

@implementation FLEXURLTransaction

+ (instancetype)withRequest:(NSURLRequest *)request startTime:(NSDate *)startTime {
    FLEXURLTransaction *transaction = [self withStartTime:startTime];
    transaction->_request = request;
    return transaction;
}

- (NSString *)primaryDescription {
    if (!_primaryDescription) {
        NSString *name = self.request.URL.lastPathComponent;
        if (!name.length) {
            name = @"/";
        }
        
        if (_request.URL.query) {
            name = [name stringByAppendingFormat:@"?%@", self.request.URL.query];
        }
        
        _primaryDescription = name;
    }
    
    return _primaryDescription;
}

- (NSString *)secondaryDescription {
    if (!_secondaryDescription) {
        NSMutableArray<NSString *> *mutablePathComponents = self.request.URL.pathComponents.mutableCopy;
        if (mutablePathComponents.count > 0) {
            [mutablePathComponents removeLastObject];
        }
        
        NSString *path = self.request.URL.host;
        for (NSString *pathComponent in mutablePathComponents) {
            path = [path stringByAppendingPathComponent:pathComponent];
        }
        
        _secondaryDescription = path;
    }
    
    return _secondaryDescription;
}

- (NSString *)tertiaryDescription {
    if (!_tertiaryDescription) {
        NSMutableArray<NSString *> *detailComponents = [NSMutableArray new];
        
        NSString *timestamp = [self timestampStringFromRequestDate:self.startTime];
        if (timestamp.length > 0) {
            [detailComponents addObject:timestamp];
        }
        
        // Omit method for GET (assumed as default)
        NSString *httpMethod = self.request.HTTPMethod;
        if (httpMethod.length > 0) {
            [detailComponents addObject:httpMethod];
        }
        
        if (self.state == FLEXNetworkTransactionStateFinished || self.state == FLEXNetworkTransactionStateFailed) {
            [detailComponents addObjectsFromArray:self.details];
        } else {
            // Unstarted, Awaiting Response, Receiving Data, etc.
            NSString *state = [self.class readableStringFromTransactionState:self.state];
            [detailComponents addObject:state];
        }
        
        _tertiaryDescription = [detailComponents componentsJoinedByString:@" ・ "];
    }
    
    return _tertiaryDescription;
}

- (NSString *)copyString {
    return self.request.URL.absoluteString;
}

- (BOOL)matchesQuery:(NSString *)filterString {
    return [self.request.URL.absoluteString localizedCaseInsensitiveContainsString:filterString];
}

@end

@interface FLEXHTTPTransaction ()
@property (nonatomic, readwrite) NSData *cachedRequestBody;
@end

@implementation FLEXHTTPTransaction

+ (instancetype)request:(NSURLRequest *)request identifier:(NSString *)requestID {
    FLEXHTTPTransaction *httpt = [self withRequest:request startTime:NSDate.date];
    httpt->_requestID = requestID;
    return httpt;
}

- (NSString *)description {
    NSString *description = [super description];
    
    description = [description stringByAppendingFormat:@" id = %@;", self.requestID];
    description = [description stringByAppendingFormat:@" url = %@;", self.request.URL];
    description = [description stringByAppendingFormat:@" duration = %f;", self.duration];
    description = [description stringByAppendingFormat:@" receivedDataLength = %lld", self.receivedDataLength];
    
    return description;
}

- (NSData *)cachedRequestBody {
    if (!_cachedRequestBody) {
        if (self.request.HTTPBody != nil) {
            _cachedRequestBody = self.request.HTTPBody;
        } else if ([self.request.HTTPBodyStream conformsToProtocol:@protocol(NSCopying)]) {
            NSInputStream *bodyStream = [self.request.HTTPBodyStream copy];
            const NSUInteger bufferSize = 1024;
            uint8_t buffer[bufferSize];
            NSMutableData *data = [NSMutableData new];
            [bodyStream open];
            NSInteger readBytes = 0;
            do {
                readBytes = [bodyStream read:buffer maxLength:bufferSize];
                [data appendBytes:buffer length:readBytes];
            } while (readBytes > 0);
            [bodyStream close];
            _cachedRequestBody = data;
        }
    }
    return _cachedRequestBody;
}

- (NSArray *)detailString {
    NSMutableArray<NSString *> *detailComponents = [NSMutableArray new];
    
    NSString *statusCodeString = [FLEXUtility statusCodeStringFromURLResponse:self.response];
    if (statusCodeString.length > 0) {
        [detailComponents addObject:statusCodeString];
    }

    if (self.receivedDataLength > 0) {
        NSString *responseSize = [NSByteCountFormatter
            stringFromByteCount:self.receivedDataLength
            countStyle:NSByteCountFormatterCountStyleBinary
        ];
        [detailComponents addObject:responseSize];
    }

    NSString *totalDuration = [FLEXUtility stringFromRequestDuration:self.duration];
    NSString *latency = [FLEXUtility stringFromRequestDuration:self.latency];
    NSString *duration = [NSString stringWithFormat:@"%@ (%@)", totalDuration, latency];
    [detailComponents addObject:duration];
    
    return detailComponents;
}

- (BOOL)displayAsError {
    return [FLEXUtility isErrorStatusCodeFromURLResponse:self.response] || super.displayAsError;
}

@end


@implementation FLEXWebsocketTransaction

+ (instancetype)withMessage:(NSURLSessionWebSocketMessage *)message
                       task:(NSURLSessionWebSocketTask *)task
                  direction:(FLEXWebsocketMessageDirection)direction
                  startTime:(NSDate *)started {
    FLEXWebsocketTransaction *wst = [self withRequest:task.originalRequest startTime:started];
    wst->_message = message;
    wst->_direction = direction;
    
    // Populate receivedDataLength
    if (direction == FLEXWebsocketIncoming) {
        wst.receivedDataLength = wst.dataLength;
        wst.state = FLEXNetworkTransactionStateFinished;
    }
    
    // Populate thumbnail image
    if (message.type == NSURLSessionWebSocketMessageTypeData) {
        wst.thumbnail = FLEXResources.binaryIcon;
    } else {
        wst.thumbnail = FLEXResources.textIcon;
    }
    
    return wst;
}

+ (instancetype)withMessage:(NSURLSessionWebSocketMessage *)message
                       task:(NSURLSessionWebSocketTask *)task
                  direction:(FLEXWebsocketMessageDirection)direction {
    return [self withMessage:message task:task direction:direction startTime:NSDate.date];
}

- (NSArray<NSString *> *)details API_AVAILABLE(ios(13.0)) {
    return @[
        self.direction == FLEXWebsocketOutgoing ? @"SENT →" : @"→ RECEIVED",
        [NSByteCountFormatter
            stringFromByteCount:self.dataLength
            countStyle:NSByteCountFormatterCountStyleBinary
        ]
    ];
}

- (int64_t)dataLength {
    if (self.message) {
        if (self.message.type == NSURLSessionWebSocketMessageTypeString) {
            return self.message.string.length;
        }
        
        return self.message.data.length;
    }
    
    return 0;
}

@end

@implementation FLEXFirebaseSetDataInfo

+ (instancetype)data:(NSDictionary *)data merge:(NSNumber *)merge mergeFields:(NSArray *)mergeFields {
    NSParameterAssert(data);
    NSParameterAssert(merge || mergeFields);

    FLEXFirebaseSetDataInfo *info = [self new];
    info->_documentData = data;
    info->_merge = merge;
    info->_mergeFields = mergeFields;

    return info;
}

@end

NSString * FLEXStringFromFIRRequestType(FLEXFIRRequestType type) {
    switch (type) {
        case FLEXFIRRequestTypeNotFirebase:
            return @"not firebase";
        case FLEXFIRRequestTypeFetchQuery:
            return @"query fetch";
        case FLEXFIRRequestTypeFetchDocument:
            return @"document fetch";
        case FLEXFIRRequestTypeSetData:
            return @"set data";
        case FLEXFIRRequestTypeUpdateData:
            return @"update data";
        case FLEXFIRRequestTypeAddDocument:
            return @"create";
        case FLEXFIRRequestTypeDeleteDocument:
            return @"delete";
    }
}

FLEXFIRTransactionDirection FIRDirectionFromRequestType(FLEXFIRRequestType type) {
    switch (type) {
        case FLEXFIRRequestTypeNotFirebase:
            return FLEXFIRTransactionDirectionNone;
        case FLEXFIRRequestTypeFetchQuery:
        case FLEXFIRRequestTypeFetchDocument:
            return FLEXFIRTransactionDirectionPull;
        case FLEXFIRRequestTypeSetData:
        case FLEXFIRRequestTypeUpdateData:
        case FLEXFIRRequestTypeAddDocument:
        case FLEXFIRRequestTypeDeleteDocument:
            return FLEXFIRTransactionDirectionPush;
    }
}

@interface FLEXFirebaseTransaction ()
@property (nonatomic) id extraData;
@end

@implementation FLEXFirebaseTransaction
//@synthesize responseString = _responseString;
//@synthesize responseObject = _responseObject;

+ (instancetype)initiator:(id)initiator requestType:(FLEXFIRRequestType)type extraData:(id)data {
    FLEXFirebaseTransaction *fire = [FLEXFirebaseTransaction withStartTime:NSDate.date];
    fire->_direction = FIRDirectionFromRequestType(type);
    fire->_initiator = initiator;
    fire->_requestType = type;
    fire->_extraData = data;
    return fire;
}

+ (instancetype)queryFetch:(FIRQuery *)initiator {
    return [self initiator:initiator requestType:FLEXFIRRequestTypeFetchQuery extraData:nil];
}

+ (instancetype)documentFetch:(FIRDocumentReference *)initiator {
    return [self initiator:initiator requestType:FLEXFIRRequestTypeFetchDocument extraData:nil];
}

+ (instancetype)setData:(FIRDocumentReference *)initiator data:(NSDictionary *)data
                  merge:(NSNumber *)merge mergeFields:(NSArray *)mergeFields {

    FLEXFirebaseSetDataInfo *info = [FLEXFirebaseSetDataInfo data:data merge:merge mergeFields:mergeFields];
    return [self initiator:initiator requestType:FLEXFIRRequestTypeSetData extraData:info];
}

+ (instancetype)updateData:(FIRDocumentReference *)initiator data:(NSDictionary *)data {
    return [self initiator:initiator requestType:FLEXFIRRequestTypeUpdateData extraData:data];
}

+ (instancetype)addDocument:(FIRCollectionReference *)initiator document:(FIRDocumentReference *)doc {
    return [self initiator:initiator requestType:FLEXFIRRequestTypeAddDocument extraData:doc];
}

+ (instancetype)deleteDocument:(FIRDocumentReference *)initiator {
    return [self initiator:initiator requestType:FLEXFIRRequestTypeDeleteDocument extraData:nil];
}

- (FIRDocumentReference *)initiator_doc {
    if ([_initiator isKindOfClass:cFIRDocumentReference]) {
        return _initiator;        
    }
    
    return nil;
}
- (FIRQuery *)initiator_query {
    if ([_initiator isKindOfClass:cFIRQuery]) {
        return _initiator;        
    }
    
    return nil;
}

- (FIRCollectionReference *)initiator_collection {
    if ([_initiator isKindOfClass:cFIRCollectionReference]) {
        return _initiator;
    }
    
    return nil;
}

- (FLEXFirebaseSetDataInfo *)setDataInfo {
    if (self.requestType == FLEXFIRRequestTypeSetData) {
        return self.extraData;
    }

    return nil;
}

- (NSDictionary *)updateData {
    if (self.requestType == FLEXFIRRequestTypeUpdateData) {
        return self.extraData;
    }

    return nil;
}

- (NSDictionary *)documentData {
    if (self.requestType == FLEXFIRRequestTypeAddDocument) {
        return self.extraData;
    }

    return nil;
}

- (NSString *)path {
    switch (self.direction) {
        case FLEXFIRTransactionDirectionNone:
            return nil;
        case FLEXFIRTransactionDirectionPush:
        case FLEXFIRTransactionDirectionPull: {
            switch (self.requestType) {
                case FLEXFIRRequestTypeNotFirebase:
                    @throw NSInternalInconsistencyException;

                case FLEXFIRRequestTypeFetchQuery:
                case FLEXFIRRequestTypeAddDocument:
                    return self.initiator_collection.path ?: @"[TBA: FIRQuerySnapshot]";
                case FLEXFIRRequestTypeFetchDocument:
                case FLEXFIRRequestTypeSetData:
                case FLEXFIRRequestTypeUpdateData:
                case FLEXFIRRequestTypeDeleteDocument:
                    return self.initiator_doc.path;
            }
        }
    }
}

- (NSString *)primaryDescription {
    if (!_primaryDescription) {
        switch (self.direction) {
            case FLEXFIRTransactionDirectionNone:
                _primaryDescription = @"";
            case FLEXFIRTransactionDirectionPush:
                _primaryDescription = @"Push; TBA";
            case FLEXFIRTransactionDirectionPull:
                _primaryDescription = self.initiator_collection.collectionID ?: self.initiator_doc.documentID;
        }
    }
    
    return _primaryDescription;
}

- (NSString *)secondaryDescription {
    if (!_secondaryDescription) {
        _secondaryDescription = self.path.stringByDeletingLastPathComponent;
    }
    
    return _secondaryDescription;
}

- (NSString *)tertiaryDescription {
    if (!_tertiaryDescription) {
        NSMutableArray<NSString *> *detailComponents = [NSMutableArray new];
        
        NSString *timestamp = [self timestampStringFromRequestDate:self.startTime];
        if (timestamp.length > 0) {
            [detailComponents addObject:timestamp];
        }
        
        [detailComponents addObject:self.direction == FLEXFIRTransactionDirectionPush ?
            @"Push ↑" : @"Pull ↓"
        ];

        if (self.direction == FLEXFIRTransactionDirectionPush) {
            [detailComponents addObjectsFromArray:@[FLEXStringFromFIRRequestType(self.requestType)]];
        }
        
        if (self.state == FLEXNetworkTransactionStateFinished || self.state == FLEXNetworkTransactionStateFailed) {
            if (self.direction == FLEXFIRTransactionDirectionPull) {
                NSString *docCount = [NSString stringWithFormat:@"%@ document(s)", @(self.documents.count)];
                [detailComponents addObjectsFromArray:@[docCount]];
            }
        } else {
            // Unstarted, Awaiting Response, Receiving Data, etc.
            NSString *state = [self.class readableStringFromTransactionState:self.state];
            [detailComponents addObject:state];
        }
        
        _tertiaryDescription = [detailComponents componentsJoinedByString:@" ・ "];
    }
    
    return _tertiaryDescription;
}

- (NSString *)copyString {
    return self.path;
}

- (BOOL)matchesQuery:(NSString *)filterString {
    if ([self.path localizedCaseInsensitiveContainsString:filterString]) {
        return YES;
    }

    BOOL isPull = self.direction == FLEXFIRTransactionDirectionPull;
    BOOL isPush = self.direction == FLEXFIRTransactionDirectionPush;

    // Allow filtering for push or pull directly
    if (isPull && [filterString localizedCaseInsensitiveCompare:@"pull"] == NSOrderedSame) {
        return YES;
    }
    if (isPush && [filterString localizedCaseInsensitiveCompare:@"push"] == NSOrderedSame) {
        return YES;
    }

    return NO;
}

//- (NSString *)responseString {
//    if (!_responseString) {
//        _responseString = [NSString stringWithUTF8String:(char *)self.response.bytes];
//    }
//    
//    return _responseString;
//}
//
//- (NSDictionary *)responseObject {
//    if (!_responseObject) {
//        _responseObject = [NSJSONSerialization JSONObjectWithData:self.response options:0 error:nil];
//    }
//    
//    return _responseObject;
//}

@end
