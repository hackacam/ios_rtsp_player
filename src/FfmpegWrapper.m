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

@interface AVFrameData : NSObject
@property (nonatomic, strong) NSMutableData *colorPlane0;
@property (nonatomic, strong) NSMutableData *colorPlane1;
@property (nonatomic, strong) NSMutableData *colorPlane2;
@property (nonatomic, strong) NSNumber      *lineWidth0;
@property (nonatomic, strong) NSNumber      *lineWidth1;
@property (nonatomic, strong) NSNumber      *lineWidth2;
@property (nonatomic, strong) NSNumber      *width;
@property (nonatomic, strong) NSNumber      *height;
@property (nonatomic, strong) NSDate        *presentationTime;
@end
@implementation AVFrameData
@synthesize colorPlane0=_colorPlane0;
@synthesize colorPlane1=_colorPlane1;
@synthesize colorPlane2=_colorPlane2;
@synthesize lineWidth0=_lineWidth0;
@synthesize lineWidth1=_lineWidth1;
@synthesize lineWidth2=_lineWidth2;
@synthesize width=_width;
@synthesize height=_height;
@synthesize presentationTime=_presentationTime;
@end

@interface FfmpegWrapper(){
    AVFormatContext *pFormatCtx;
    AVCodecContext  *pCodecCtx;
    AVCodec         *pCodec;
    AVFrame         *pFrame;
    AVFrame         *pFrameRGB;
    AVPacket        packet;
    uint8_t         *buffer;
    AVDictionary    *optionsDict;
    struct SwsContext      *sws_ctx;
    int videoStream;
}

@property (nonatomic, strong) NSMutableArray * outputImageArray;
@property (nonatomic, strong) UIImage *outputImage;
@end

@implementation FfmpegWrapper

@synthesize pauseDecode = _pauseDecode;
@synthesize outputImageArray = _outputImageArray;
@synthesize outputImage = _outputImage;

-(NSMutableArray *) outputImageArray
{
    if (!_outputImageArray){
        _outputImageArray = [[NSMutableArray alloc] init];
    }
    return _outputImageArray;
}

-(NSNumber *) pauseDecode
{
    if (!_pauseDecode){
        _pauseDecode = [NSNumber numberWithInt:0];
    }
    return _pauseDecode;
}

-(id) init
{
    self=[super init];
    // initialize all instance variables
    pFormatCtx = NULL;
    pCodecCtx = NULL;
    pCodec = NULL;
    pFrame = NULL;
    pFrameRGB = NULL;
    buffer = NULL;
    optionsDict = NULL;
    sws_ctx = NULL;
    
    // register av
    av_register_all();
    avformat_network_init();
    
    return self;
}

-(int) connectRTSPServer:(NSString *)url
{
    // open video stream
    AVDictionary *serverOpt = NULL;
    av_dict_set(&serverOpt, "rtsp_transport", "tcp", 0);
    if (avformat_open_input(&pFormatCtx, [url UTF8String], NULL, &serverOpt)!=0){
        NSLog(@"error opening stream");
        return -1; // Couldn't open file
    }

    // a hack
//    pFormatCtx->streams[0]->codec->width=1920;
    
    // Retrieve stream information
    AVDictionary * options = NULL;
    av_dict_set(&options, "analyzeduration", "1000000", 0);
    
    if(avformat_find_stream_info(pFormatCtx, &options)<0)
        return -1; // Couldn't find stream information
    
    // Dump information about file onto standard error
    av_dump_format(pFormatCtx, 0, [url UTF8String], 0);
    
    // Find the first video stream
    videoStream=-1;
    for(int i=0; i<pFormatCtx->nb_streams; i++)
        if(pFormatCtx->streams[i]->codec->codec_type==AVMEDIA_TYPE_VIDEO) {
            videoStream=i;
            break;
        }
    if(videoStream==-1)
        return -1; // Didn't find a video stream
    
    // Get a pointer to the codec context for the video stream
    pCodecCtx=pFormatCtx->streams[videoStream]->codec;
    
    // Find the decoder for the video stream
    pCodec=avcodec_find_decoder(pCodecCtx->codec_id);
    if(pCodec==NULL) {
        fprintf(stderr, "Unsupported codec!\n");
        return -1; // Codec not found
    }
    // Open codec
    if(avcodec_open2(pCodecCtx, pCodec, &optionsDict)<0)
        return -1; // Could not open codec
    
    // Allocate video frame
    pFrame=avcodec_alloc_frame();
    
    // Allocate an AVFrame structure
    pFrameRGB=avcodec_alloc_frame();
    if(pFrameRGB==NULL)
        return -1;
    
    // Determine required buffer size and allocate buffer
    int numBytes=avpicture_get_size(PIX_FMT_RGB24, pCodecCtx->width,
                                    pCodecCtx->height);
    buffer=(uint8_t *)av_malloc(numBytes*sizeof(uint8_t));
    
    sws_ctx =
    sws_getContext
    (
     pCodecCtx->width,
     pCodecCtx->height,
     pCodecCtx->pix_fmt,
     pCodecCtx->width,
     pCodecCtx->height,
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
                   pCodecCtx->width, pCodecCtx->height);

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

-(int) startDecodingWithCallbackBlock: (void (^) (unsigned char * yData,
                                                  int  yLineSize,
                                                  unsigned char * uData,
                                                  int  uLineSize,
                                                  unsigned char * vData,
                                                  int  vLineSize,
                                                  unsigned long timestamp,
                                                  int width,
                                                  int height)) frameCallbackBlock
                   imageCallbackBlock: (void (^) (UIImage * image,
                                                  unsigned long timestamp)) imageCallbackBlock
                   completionCallback: (void (^)()) completion
{
    dispatch_queue_t decodeQueue = dispatch_queue_create("decodeQueue", NULL);
    dispatch_async(decodeQueue, ^{
        int frameFinished;
        NSLog(@"%@", self.pauseDecode);
        while (av_read_frame(pFormatCtx, &packet)>=0 && [self.pauseDecode intValue]==0) {
            // Is this a packet from the video stream?
            if(packet.stream_index==videoStream) {
                // Decode video frame
                avcodec_decode_video2(pCodecCtx, pFrame, &frameFinished,
                                      &packet);
                
                // Did we get a video frame?
                if(frameFinished) {
                    // run the block callback
                    frameCallbackBlock(pFrame->data[0], pFrame->linesize[0],
                                       pFrame->data[1], pFrame->linesize[1],
                                       pFrame->data[2], pFrame->linesize[2],
                                       av_frame_get_best_effort_timestamp(pFrame),
                                       pFrame->width,
                                       pFrame->height);
//                    if (imageCallbackBlock){ // convert to UIImage
                    sws_scale
                    (
                     sws_ctx,
                     (uint8_t const * const *)pFrame->data,
                     pFrame->linesize,
                     0,
                     pCodecCtx->height,
                     pFrameRGB->data,
                     pFrameRGB->linesize
                     );
                    UIImage *image = [self imageFromAVPicture:pFrameRGB->data
                                                     lineSize:pFrameRGB->linesize
                                                        width:pFrame->width height:pFrame->height];
                    
                    if (self.outputImageArray.count < 8){
                        [self.outputImageArray addObject:image];
                    }
                    if (self.outputImageArray.count > 2) {
                        self.outputImage = [self.outputImageArray objectAtIndex:0];
                        [self.outputImageArray removeObjectAtIndex:0];
                        imageCallbackBlock(self.outputImage, 0);
                    }
                    //                    }
                }
            }
            
            // Free the packet that was allocated by av_read_frame
            av_free_packet(&packet);
        }
        completion();
    });
    return 0;
}

-(void)dealloc {
    // Free the RGB image
    av_free(buffer);
    av_free(pFrameRGB);
    
    // Free the YUV frame
    av_free(pFrame);
    
    // Close the codec
    if (pCodecCtx){
        avcodec_close(pCodecCtx);
    }
    
    // Close the video src
    if (pFormatCtx){
        avformat_close_input(&pFormatCtx);
    }

}
@end
