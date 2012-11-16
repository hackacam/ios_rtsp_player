//
//  FfmpegWrapper.m
//  rtsp_ffmpeg_player
//
//  Created by J.C. Li on 11/2/12.
//  Copyright (c) 2012 J.C. Li. All rights reserved.
//


#import "FfmpegWrapper.h"
#import <FFmpegDecoder/libavcodec/avcodec.h>
#import <FFmpegDecoder/libavformat/avformat.h>
#import <FFmpegDecoder/libswscale/swscale.h>
#include <libkern/OSAtomic.h>

@interface AVFrameData : NSObject
@property (nonatomic, strong) NSMutableData *colorPlane0;
@property (nonatomic, strong) NSMutableData *colorPlane1;
@property (nonatomic, strong) NSMutableData *colorPlane2;
@property (nonatomic, strong) NSNumber      *lineSize0;
@property (nonatomic, strong) NSNumber      *lineSize1;
@property (nonatomic, strong) NSNumber      *lineSize2;
@property (nonatomic, strong) NSNumber      *width;
@property (nonatomic, strong) NSNumber      *height;
@property (nonatomic, strong) NSDate        *presentationTime;

-(id) initWithAVFrame: (AVFrame *) frame;

@end
@implementation AVFrameData
@synthesize colorPlane0=_colorPlane0;
@synthesize colorPlane1=_colorPlane1;
@synthesize colorPlane2=_colorPlane2;
@synthesize lineSize0=_lineSize0;
@synthesize lineSize1=_lineSize1;
@synthesize lineSize2=_lineSize2;
@synthesize width=_width;
@synthesize height=_height;
@synthesize presentationTime=_presentationTime;

-(id) initWithAVFrame: (AVFrame *) frame
{
    self = [super init];
    self.colorPlane0 = [[NSMutableData alloc] initWithBytes:frame->data[0] length:frame->linesize[0]];
    self.colorPlane1 = [[NSMutableData alloc] initWithBytes:frame->data[1] length:frame->linesize[1]];
    self.colorPlane2 = [[NSMutableData alloc] initWithBytes:frame->data[2] length:frame->linesize[2]];
    self.lineSize0 = [[NSNumber alloc] initWithInt:frame->linesize[0]];
    self.lineSize1 = [[NSNumber alloc] initWithInt:frame->linesize[1]];
    self.lineSize2 = [[NSNumber alloc] initWithInt:frame->linesize[2]];
    self.width = [[NSNumber alloc] initWithInt:frame->width];
    self.height = [[NSNumber alloc] initWithInt:frame->height];

    return self;
}

@end

@interface FfmpegWrapper(){
    AVFormatContext *_formatCtx;
    AVCodecContext  *_codecCtx;
    AVCodec         *_codec;
    AVFrame         *_frame;
    AVPacket        _packet;
    AVDictionary    *_optionsDict;
    int _videoStream;
    
    dispatch_semaphore_t _outputSinkQueueSema;
    
    volatile bool _stopDecode;
}

@end

@implementation FfmpegWrapper

-(id) init
{
    self=[super init];
    // initialize all instance variables
    _formatCtx = NULL;
    _codecCtx = NULL;
    _codec = NULL;
    _frame = NULL;
    _optionsDict = NULL;
    
    // register av
    av_register_all();
    avformat_network_init();
    
    // setup output queue depth;
    _outputSinkQueueSema = dispatch_semaphore_create((long)(5));
    
    // set memory barrier
    OSMemoryBarrier();
    _stopDecode=false;
    
    return self;
}

-(int) openUrl: (NSString *) url
{
    if (_formatCtx!=NULL || _codec!=NULL){
        return -1;  //url already opened
    }
    
    // open video stream
    AVDictionary *serverOpt = NULL;
    av_dict_set(&serverOpt, "rtsp_transport", "tcp", 0);
    if (avformat_open_input(&_formatCtx, [url UTF8String], NULL, &serverOpt)!=0){
        NSLog(@"error opening stream");
        [self dealloc_helper];
        return -1; // Couldn't open file
    }
    
    // Retrieve stream information
    AVDictionary * options = NULL;
    av_dict_set(&options, "analyzeduration", "1000000", 0);
    
    if(avformat_find_stream_info(_formatCtx, &options)<0){
        [self dealloc_helper];
        return -1; // Couldn't find stream information
    }
    
    // Dump information about file onto standard error
    av_dump_format(_formatCtx, 0, [url UTF8String], 0);
    
    // Find the first video stream
    _videoStream=-1;
    for(int i=0; i<_formatCtx->nb_streams; i++)
        if(_formatCtx->streams[i]->codec->codec_type==AVMEDIA_TYPE_VIDEO) {
            _videoStream=i;
            break;
        }
    if(_videoStream==-1){
        [self dealloc_helper];
        return -1; // Didn't find a video stream
    }
    
    // Get a pointer to the codec context for the video stream
    _codecCtx=_formatCtx->streams[_videoStream]->codec;
    
    // Find the decoder for the video stream
    _codec=avcodec_find_decoder(_codecCtx->codec_id);
    if(_codec==NULL) {
        fprintf(stderr, "Unsupported codec!\n");
        [self dealloc_helper];
        return -1; // Codec not found
    }
    // Open codec
    if(avcodec_open2(_codecCtx, _codec, &_optionsDict)<0)
        [self dealloc_helper];
        return -1; // Could not open codec
    
    // Allocate video frame
    _frame=avcodec_alloc_frame();
    if (!_frame){
        [self dealloc_helper];
        return -1;  // Could not allocate frame buffer
    }
    return 0;
}

-(UIImage *)imageFromAVPicture:(unsigned char **)picData
                      lineSize:(int *) linesize
                         width:(int)width height:(int)height {
	CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
	CFDataRef data = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, picData[0], linesize[0]*height,kCFAllocatorNull);
	CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGImageRef cgImage = CGImageCreate(width,
									   height,
									   8,
									   24,
									   linesize[0],
									   colorSpace,
									   bitmapInfo,
									   provider,
									   NULL,
									   NO,
									   kCGRenderingIntentDefault);
	CGColorSpaceRelease(colorSpace);
	UIImage *image = [UIImage imageWithCGImage:cgImage];
	CGImageRelease(cgImage);
	CGDataProviderRelease(provider);
	CFRelease(data);
	
	return image;
}

-(void) stopDecode
{
    _stopDecode = true;
}

-(int) startDecodingWithCallbackBlock: (void (^) (AVFrameData *frame)) frameCallbackBlock
                      waitForConsumer: (BOOL) wait
                   completionCallback: (void (^)()) completion
{
    OSMemoryBarrier();
    _stopDecode=false;
    dispatch_queue_t decodeQueue = dispatch_queue_create("decodeQueue", NULL);
    dispatch_queue_t outputSinkQueue = dispatch_queue_create("outputSink", NULL);
    dispatch_async(decodeQueue, ^{
        int frameFinished;
        OSMemoryBarrier();
        while (self->_stopDecode==false){
            if (av_read_frame(_formatCtx, &_packet)>=0) {
                // Is this a packet from the video stream?
                if(_packet.stream_index==_videoStream) {
                    // Decode video frame
                    avcodec_decode_video2(_codecCtx, _frame, &frameFinished,
                                          &_packet);
                    
                    // Did we get a video frame?
                    if(frameFinished) {
                        // see if the queue is full;
                        long waitSignal;
                        if (wait){
                            waitSignal = dispatch_semaphore_wait(_outputSinkQueueSema, DISPATCH_TIME_FOREVER);
                        }else{
                            waitSignal = dispatch_semaphore_wait(_outputSinkQueueSema, DISPATCH_TIME_NOW);
                        }
                        if (waitSignal==0){
                            dispatch_async(outputSinkQueue, ^{
                                // create a frame object and call the block;
                                AVFrameData *frameData = [[AVFrameData alloc] initWithAVFrame:_frame];
                                frameCallbackBlock(frameData);
                                // signal the output sink semaphore
                                dispatch_semaphore_signal(_outputSinkQueueSema);
                            });
                        }
                    }
                }
                
                // Free the packet that was allocated by av_read_frame
                av_free_packet(&_packet);
            }
        }
        completion();
    });
    return 0;
}

-(void)dealloc_helper
{
    // Free the YUV frame
    if (_frame){
        av_free(_frame);
    }
    // Close the codec
    if (_codecCtx){
        avcodec_close(_codecCtx);
    }
    // Close the video src
    if (_formatCtx){
        avformat_close_input(&_formatCtx);
    }
}

-(void)dealloc {
    [self dealloc_helper];
}

@end
