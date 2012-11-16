//
//  FfmpegWrapper.h
//  rtsp_ffmpeg_player
//
//  Created by J.C. Li on 11/2/12.
//  Copyright (c) 2012 J.C. Li. All rights reserved.
//

#import <Foundation/Foundation.h>

@class AVFrameData;

@interface FfmpegWrapper : NSObject

-(id) init;

//-(id) initWithOutputFormat: (NSString *) format;

-(int) openUrl: (NSString *) url;

-(int) startDecodingWithCallbackBlock: (void (^) (AVFrameData *frame)) frameCallbackBlock
                      waitForConsumer: (BOOL) wait
                   completionCallback: (void (^)()) completion;

-(void) stopDecode;

@end
