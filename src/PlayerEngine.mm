//
//  PlayerEngine.mm
//  uPlayer
//
//  Created by liaogang on 15/1/27.
//  Copyright (c) 2015年 liaogang. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#import "PlayerEngine.h"
#import "PlayerMessage.h"
#import "PlayerTypeDefines.h"
#import "UPlayer.h"



const NSTimeInterval timeInterval = 0.2;

@interface PlayerEngine ()
<AVAudioPlayerDelegate>
{
    PlayState _state;
    BOOL firstLoaded;
    int justSeeked;
    float _volume;
}

@property (nonatomic,strong) AVAudioPlayer  *player;
@property (nonatomic,strong) NSTimer *timer;




@property (nonatomic,strong) AVAudioFormat *audioFormat;
@property (nonatomic,strong) AVAudioPCMBuffer* pcmBuffer;
@property (nonatomic,strong) FFTSampleBlock* sampleBlock;
@end

@implementation FFTSampleBlock

+(int)getSampleLength
{
    return 2048;
}

@end

void getSampleBlockInBufferAtTime(AVAudioPCMBuffer* pcmBuffer, AVAudioFormat *audioFormat, NSTimeInterval time,FFTSampleBlock* sampleBlock);


@implementation PlayerEngine


-(instancetype)init
{
    self = [super init];
    if (self)
    {
        firstLoaded = true;
        _state = playstate_stopped;
        _progressInfo = [ProgressInfo new];

        

        
        
        addObserverForEvent(self, @selector(playNext), EventID_track_stopped_playnext);
        
        addObserverForEvent(self, @selector(actionPlayNext), EventID_to_play_next);
        
        addObserverForEvent(self, @selector(needResumePlayAtBoot), EventID_player_document_loaded);
       
        addObserverForEvent(self, @selector(stop), EventID_to_stop);
        
        addObserverForEvent(self, @selector(playPause), EventID_to_play_pause_resume);
        
        addObserverForEvent(self, @selector(actionPlayRandom), EventID_to_play_random);
        
        [NSTimer scheduledTimerWithTimeInterval:timeInterval target:self selector:@selector(timerComing) userInfo:nil repeats:YES];
        
    }
    
    return self;
}
    
-(void)timerComing
{
    if (justSeeked > 0)
    {
        justSeeked-=1;
    }
    else
    {
        if ( _state == playstate_playing )
        {
            _progressInfo.current += timeInterval;
            
            postEvent(EventID_track_progress_changed, _progressInfo);
            
            
            if (self.sampleBlock == nil) {
                self.sampleBlock = [[FFTSampleBlock alloc]init];
            }
            
            
            
            getSampleBlockInBufferAtTime(self.pcmBuffer, self.audioFormat, self.player.currentTime , self.sampleBlock);
            postEvent(EventID_to_draw_spectrum, self.sampleBlock);
            
        }
    }
    
}
    
-(void)needResumePlayAtBoot
{
    PlayerDocument *doc = player().document;
    if (doc.resumeAtReboot && doc.playState != playstate_stopped )
    {
        PlayerTrack *track = Playing();
        PlayerList *list = track.list;
        
        _volume = doc.volume;
        
        if ( doc.playState == playstate_paused )
            playTrackPauseAfterInit( list, track );
        else if( doc.playState == playstate_playing) {
            playTrack(track);
        }
        
        if (doc.playTime > 0) {
            [self seekToTime:doc.playTime];
        }
        
    }
}


-(void)didReachFileEnd
{
    _state = playstate_stopped;
    postEvent(EventID_track_stopped_playnext, nil);
    
    if( player().document.trackSongsWhenPlayStarted)
        postEvent(EventID_to_reload_tracklist, Playing());
}

// action by user.
-(void)actionPlayNext
{
    [self playNext];
    PlayerTrack *track = Playing();
    postEvent(EventID_to_reload_tracklist, track );
}

-(void)playNext
{
    PlayerDocument *d = player().document;
    PlayerQueue *queue = d.playerQueue;
    
    PlayerTrack *trackQueue = [queue pop] ;
    if ( trackQueue )
    {
        // send stop
        setPlaying(nil);
        _state = playstate_stopped;
        postEvent(EventID_track_stopped, nil);
        postEvent(EventID_track_state_changed, nil);
        
        
        playTrack(trackQueue);
    }
    else
    {
        PlayerTrack *track = Playing();
        PlayerList *list = track.list;
    
        
        // send stop
        setPlaying(nil);
        
        _state = playstate_stopped;
        postEvent(EventID_track_stopped, nil);
        postEvent(EventID_track_state_changed, nil);
        
        assert(list);
        
        
        int index = (int)track.index;
        int count = (int)[list count];
        if(count > 0)
        {
            int indexNext =-1;
            PlayOrder order = (PlayOrder)d.playOrder;
            
            if (order == playorder_single) {
                [self stop];
            }
            else if (order == playorder_default)
            {
                indexNext = index +1;
            }
            else if(order == playorder_random)
            {
                static int s=0;
                if(s++==0)
                    srand((uint )time(NULL));
                
                indexNext =rand() % (count);
            }else if(order == playorder_repeat_single)
            {
                playTrack(track);
                return;
                
            }else if(order == playorder_repeat_list)
            {
                indexNext = index + 1;
                if ( indexNext == count )
                    indexNext = 0;
            }
            
            
            track = nil;
            if ( indexNext >= 0 && indexNext < [list count] )
                track = [list getItem: indexNext ];
            
            
            playTrack(track);
        }
    }
}

-(void)dealloc
{
    removeObserver(self);
}

-(PlayState)getPlayState
{
    return _state;
}

-(BOOL)isPlaying
{
    return _state == playstate_playing;
}

-(bool)isPaused
{
    return _state == playstate_paused;
}

-(bool)isStopped
{
    return  _state == playstate_stopped;
}

-(bool)isPending
{
    return _state == playstate_pending;
}

// by user
-(void)actionPlayRandom
{
    PlayerDocument *d = player().document;
    
    PlayerTrack *track = Playing();
    
    const PlayerList *list = track.list;
    
    if (!list)
        list = [d.playerlList getSelectedItem] ;
    
    assert(list);
    
    int count = (int)[list count];
    
    static int s=0;
    if(s++==0)
        srand((uint )time(NULL));
    
    int indexNext =rand() % (count) - 1;
    
    PlayerTrack* next = nil;
    
    if ( indexNext > 0 && indexNext < [list count] )
        next = [list getItem: indexNext ];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        playTrack(next);
    });
    
    postEvent(EventID_to_reload_tracklist, next );
}

-(void)playPause
{
    if (self.isPlaying) {
        [self.player pause];
        _state = playstate_paused ;
        postEvent(EventID_track_paused, nil);
    }
    else if (self.isPaused)
    {
        [self.player play];
        _state = playstate_playing ;
        postEvent(EventID_track_resumed, nil);
    }
    
    
    postEvent(EventID_track_state_changed, nil);
}


-(void)seekToTime:(NSTimeInterval)time
{
    justSeeked = 2;
    _progressInfo.current = time + 2 * timeInterval;
 
    
    self.player.currentTime = time;
    
}

#pragma mark - AVAudioPlayer Delegate
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    [self didReachFileEnd];
}

- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError * __nullable)error
{
    NSLog(@"audioPlayerDecodeErrorDidOccur,error: %@",error);
}





// if time is -1,it will be ignored
-(BOOL)playURL:(NSURL *)url initPaused:(bool)initPaused time:(NSTimeInterval)time
{
    NSURL* fileURL = url;
    AVAudioFile *audioFile = [[AVAudioFile alloc] initForReading:fileURL error:nil];
    self.audioFormat = audioFile.processingFormat;
    uint32 audioFrameCount = (uint32)audioFile.length;
    self.pcmBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:self.audioFormat frameCapacity: audioFrameCount];
    
    NSError *errorRead = nil;
    [audioFile readIntoBuffer:self.pcmBuffer error: &errorRead ];
    if (errorRead) {
        NSLog(@"readIntoBuffer error: %@",errorRead);
    }
    

    
   
    
   
    
    NSError *error;
    self.player = [[AVAudioPlayer alloc]initWithContentsOfURL:url error:&error];
    self.player.volume = _volume;
    
    if (error)
    {
        NSLog(@"error: %@",error);
        return FALSE;
    }
    else
    {
        self.player.delegate = self;
        
        if (time != -1)
            self.player.currentTime = time;
        
        
        if ( initPaused ) {
            [self.player pause];
            _state = playstate_paused;
        }
        else{
            [self.player play];
            _state = playstate_playing;
        }
        
        
        _progressInfo.current = self.player.currentTime;
        _progressInfo.total = self.player.duration;
        postEvent(EventID_track_started, _progressInfo );
        postEvent(EventID_track_state_changed, nil);
        
        
        return TRUE;
    }
}


-(void)stopInner
{
    [self.player stop];
    
    _state = playstate_stopped;
    
    postEvent(EventID_track_stopped, nil);
    postEvent(EventID_track_state_changed, nil);
}


-(void)stop
{
    [self.player pause];
    _state = playstate_stopped;
    
    setPlaying(nil);
    
    postEvent(EventID_track_stopped, nil);
    postEvent(EventID_track_state_changed, nil);
}


-(void)stop2
{
    [self.player pause];
    _state = playstate_stopped;
    
    
    postEvent(EventID_track_stopped, nil);
    postEvent(EventID_track_state_changed, nil);
}




-(PlayStateTime)close
{
    PlayStateTime st;
    st.time = _progressInfo.current;
    st.state = [self getPlayState];
    st.volume = self.volume;
    [self stopInner];
    return st;
}

- (void)setVolume:(float)volume
{
    _volume = volume;
    self.player.volume = volume;
}

- (float)volume
{
    return self.player.volume;
}

@end



@implementation ProgressInfo



@end



void getSampleBlockInBufferAtTime(AVAudioPCMBuffer* pcmBuffer, AVAudioFormat *audioFormat, NSTimeInterval time,FFTSampleBlock* sampleBlock)
{
    sampleBlock.pSampleR = nil;
    
    //the display may have delay.
    const int offset = 420;
    
    if( pcmBuffer.floatChannelData )
    {
        Float32 *leftChannelBuffer = pcmBuffer.floatChannelData [0];
        Float32 *rightChannelBuffer = pcmBuffer.floatChannelData [ 1];
        
        sampleBlock.pSampleL = leftChannelBuffer +((int)(time * audioFormat.sampleRate) - FFT_SAMPLE_SIZE/2 + offset);
        sampleBlock.pSampleR = rightChannelBuffer +((int)(time * audioFormat.sampleRate) - FFT_SAMPLE_SIZE/2 + offset );
        
    }
    else if(pcmBuffer.int16ChannelData)
    {
    }
    else if( pcmBuffer.int32ChannelData)
    {
    }
    else
    {
        //can not be here.
        assert(false);
    }

}

