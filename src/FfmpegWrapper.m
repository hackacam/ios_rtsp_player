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
    
    dispatch_group_t _decode_queue_group;
    
    volatile bool _stopDecode;
    
    CFTimeInterval _previousDecodedFrameTime;
}

@end

@implementation FfmpegWrapper
#define MIN_FRAME_INTERVAL 0.01

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
    
    _decode_queue_group = dispatch_group_create();
    
    // set memory barrier
    OSMemoryBarrier();
    _stopDecode=false;

    _previousDecodedFrameTime=0;
    
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
    if(avcodec_open2(_codecCtx, _codec, &_optionsDict)<0){
        [self dealloc_helper];
        return -1; // Could not open codec
    }
    
    // Allocate video frame
    _frame=avcodec_alloc_frame();
    if (!_frame){
        [self dealloc_helper];
        return -1;  // Could not allocate frame buffer
    }
    return 0;
}

-(AVFrameData *) createFrameData: (AVFrame *) frame
                     trimPadding: (BOOL) trim
{
    AVFrameData *frameData = [[AVFrameData alloc] init];
    if (trim){
        frameData.colorPlane0 = [[NSMutableData alloc] init];
        frameData.colorPlane1 = [[NSMutableData alloc] init];
        frameData.colorPlane2 = [[NSMutableData alloc] init];
        for (int i=0; i<frame->height; i++){
            [frameData.colorPlane0 appendBytes:(void*) (frame->data[0]+i*frame->linesize[0])
                                        length:frame->width];
        }
        for (int i=0; i<frame->height/2; i++){
            [frameData.colorPlane1 appendBytes:(void*) (frame->data[1]+i*frame->linesize[1])
                                        length:frame->width/2];
            [frameData.colorPlane2 appendBytes:(void*) (frame->data[2]+i*frame->linesize[2])
                                        length:frame->width/2];
        }
        frameData.lineSize0 = [[NSNumber alloc] initWithInt:frame->width];
        frameData.lineSize1 = [[NSNumber alloc] initWithInt:frame->width/2];
        frameData.lineSize2 = [[NSNumber alloc] initWithInt:frame->width/2];
    }else{
        frameData.colorPlane0 = [[NSMutableData alloc] initWithBytes:frame->data[0] length:frame->linesize[0]*frame->height];
        frameData.colorPlane1 = [[NSMutableData alloc] initWithBytes:frame->data[1] length:frame->linesize[1]*frame->height/2];
        frameData.colorPlane2 = [[NSMutableData alloc] initWithBytes:frame->data[2] length:frame->linesize[2]*frame->height/2];
        frameData.lineSize0 = [[NSNumber alloc] initWithInt:frame->linesize[0]];
        frameData.lineSize1 = [[NSNumber alloc] initWithInt:frame->linesize[1]];
        frameData.lineSize2 = [[NSNumber alloc] initWithInt:frame->linesize[2]];
    }
    frameData.width = [[NSNumber alloc] initWithInt:frame->width];
    frameData.height = [[NSNumber alloc] initWithInt:frame->height];
    return frameData;
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
    dispatch_async(decodeQueue, ^{
        int frameFinished;
        OSMemoryBarrier();
        while (self->_stopDecode==false){
            @autoreleasepool {
                CFTimeInterval currentTime = CACurrentMediaTime();
                if ((currentTime-_previousDecodedFrameTime) > MIN_FRAME_INTERVAL &&
                    av_read_frame(_formatCtx, &_packet)>=0) {
                    _previousDecodedFrameTime = currentTime;
                    // Is this a packet from the video stream?
                    if(_packet.stream_index==_videoStream) {
                        // Decode video frame
                        avcodec_decode_video2(_codecCtx, _frame, &frameFinished,
                                              &_packet);
                        
                        // Did we get a video frame?
                        if(frameFinished) {
                            // create a frame object and call the block;
                            AVFrameData *frameData = [self createFrameData:_frame trimPadding:YES];
                            frameCallbackBlock(frameData);
                        }
                    }
                    
                    // Free the packet that was allocated by av_read_frame
                    av_free_packet(&_packet);
                }else{
                    usleep(1000);
                }
            }
        }
        completion();
    });
    return 0;
}


+(UIImage *)imageFromAVPicture:(unsigned char **)picData
                      lineSize:(int *) linesize
                         width:(int)width height:(int)height
{
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

+(UIImage *) convertFrameDataToImage: (AVFrameData *) avFrameData
{
    // Allocate an AVFrame structure
    AVFrame *pFrameRGB=avcodec_alloc_frame();
    if(pFrameRGB==NULL)
        return nil;
    
    // Determine required buffer size and allocate buffer
    int numBytes=avpicture_get_size(PIX_FMT_RGB24, avFrameData.width.intValue,
                                    avFrameData.height.intValue);
    uint8_t *buffer=(uint8_t *)av_malloc(numBytes*sizeof(uint8_t));
    
    struct SwsContext *sws_ctx =
    sws_getContext
    (
     avFrameData.width.intValue,
     avFrameData.height.intValue,
     PIX_FMT_YUV420P,
     avFrameData.width.intValue,
     avFrameData.height.intValue,
     PIX_FMT_RGB24,
     SWS_BILINEAR,
     NULL,
     NULL,
     NULL
     );
    
    // Assign appropriate parts of buffer to image planes in pFrameRGB
    // Note that pFrameRGB is an AVFrame, but AVFrame is a superset
    // of AVPicture
    avpicture_fill((AVPicture *)pFrameRGB, buffer, PIX_FMT_RGB24,
                   avFrameData.width.intValue, avFrameData.height.intValue);
    
    uint8_t *data[AV_NUM_DATA_POINTERS];
    int linesize[AV_NUM_DATA_POINTERS];
    for (int i=0; i<AV_NUM_DATA_POINTERS; i++){
        data[i] = NULL;
        linesize[i] = 0;
    }
    data[0]=(uint8_t*)(avFrameData.colorPlane0.bytes);
    data[1]=(uint8_t*)(avFrameData.colorPlane1.bytes);
    data[2]=(uint8_t*)(avFrameData.colorPlane2.bytes);
    linesize[0]=avFrameData.lineSize0.intValue;
    linesize[1]=avFrameData.lineSize1.intValue;
    linesize[2]=avFrameData.lineSize2.intValue;
    
    sws_scale
    (
     sws_ctx,
     (uint8_t const * const *)data,
     linesize,
     0,
     avFrameData.width.intValue,
     pFrameRGB->data,
     pFrameRGB->linesize
     );
    UIImage *image = [self imageFromAVPicture:pFrameRGB->data
                                     lineSize:pFrameRGB->linesize
                                        width:avFrameData.width.intValue height:avFrameData.height.intValue];
    
    // Free the RGB image
    av_free(buffer);
    av_free(pFrameRGB);

    return image;
}

-(void)dealloc_helper
{
    // Close the codec
    if (_codecCtx){
        avcodec_close(_codecCtx);
    }
    // Close the video src
    if (_formatCtx){
        avformat_close_input(&_formatCtx);
    }
    // Free the YUV frame
    if (_frame){
        av_freep(_frame);
    }

}

-(void)dealloc
{
//    dispatch_group_wait(_decode_queue_group, DISPATCH_TIME_FOREVER);
    [self stopDecode];
    sleep(1);
    [self dealloc_helper];
    NSLog(@"cleaned up...");
}

@end
