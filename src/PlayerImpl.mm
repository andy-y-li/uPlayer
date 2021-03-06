//
//  PlayerImpl.mm
//  uPlayer
//
//  Created by liaogang on 15/1/27.
//  Copyright (c) 2015年 liaogang. All rights reserved.
//

#import "PlayerTrack.h"
#import "audioTag2.h"

#import "fileCtrl.h"
#import "threadpool.h"

#import "UPlayer.h"
#import "PlayerMessage.h"
#import "PlayerError.h"

#import "PlayerSerialize.h"

#include "stringConv.h"





TrackInfo* getId3Info(NSString *filename)
{
    NSMutableString *artist=[NSMutableString string];
    NSMutableString *title=[NSMutableString string];
    NSMutableString *album=[NSMutableString string];
    NSMutableString *genre=[NSMutableString string];
    NSMutableString *year=[NSMutableString string];
    
    if(getID3Info(filename.UTF8String, artist, title, album,genre,year) )
    {
        TrackInfo* at = [[TrackInfo alloc]init];
        at.artist=artist;
        at.title=title;
        at.album=album;
        at.genre=genre;
        
        if([at.genre isEqualToString:@"null"])
            at.genre=@"";
        
        at.year=year;
        
        if(!at.year)
            at.year = @"";
        return at;
    }
    else
    {
        return nil;
    }
    
}


void* addJobIsFileAudio(const char * file ,void *arg)
{
    NSMutableArray *array = (__bridge NSMutableArray*)arg;
    
    TrackInfo *arti = getId3Info([NSString stringWithUTF8String:file]);
    
    if (arti) {
        arti.path = [NSString stringWithUTF8String:file];
        
        [array addObject:arti];
    }
    
    return nil;
}


NSArray* enumAudioFiles(NSString* path)
{
    NSMutableArray *array = [NSMutableArray array];
    
    pool_init(8);
    
    IterFiles(std::string (path.UTF8String ), std::string (path.UTF8String ), addJobIsFileAudio, (__bridge void*)array );
    
    pool_destroy();
    
    return array;
}



@implementation PlayerEngine (playTrack)
-(void)playTrackInfo:(PlayerTrack*)track initPaused:(bool)paused time:(NSTimeInterval)time;
{
    NSString *path = track.info.path;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath: path])
    {
        setPlaying(track);
        [self playURL:[NSURL fileURLWithPath: path] initPaused:paused time: time ];
    }
    else
    {
        [self stop2];
        
        postEvent(EventID_play_error_happened, [PlayerError errorNoSuchFile: path]);
    }
    
}
@end


void playTrack(PlayerTrack *track)
{
    if (track)
    {
        setPlaying(track);
        
        [player().engine playTrackInfo:track initPaused:false time:-1 ];
        
        // playing track index changed.
        postEvent( EventID_to_save_config, nil);
        
    }
    
}

void playTrackPauseAfterInit(PlayerList *list,PlayerTrack *track)
{
    if (track)
        [player().engine playTrackInfo:track initPaused:true time:-1 ];
}

void collectInfo(PlayerDocument *d , PlayerEngine *e)
{
    PlayStateTime st = [e close];
    d.playTime = st.time;
    d.playState = st.state;
    d.volume = st.volume;
}




@implementation PlayerDocument (documentLoaded)

-(void)willSaveConfig
{
    PlayerTrack *track = Playing();
    self.playingIndexTrack = (int)track.index;
    self.playingIndexList = (int)[player().document.playerlList getIndex: track.list];
}

-(void)didLoad
{
    [self.playerlList didLoad];
    
    if (self.playingIndexList >= 0 && self.playingIndexTrack >= 0)
        setPlaying( [[self.playerlList getItem: self.playingIndexList] getItem: self.playingIndexTrack]);
    
}

@end

@implementation PlayerlList (documentLoaded)

-(void)willSave
{
    self.selectIndex =  (int) [self getIndex:(PlayerList*) [self getSelectedItem]];
}

-(void)didLoad
{
    if( self.selectIndex != -1)
        self.selectItem = [self getItem: self.selectIndex];
    
    for (PlayerList *list in self.playerlList) {
        if (list.type == type_temporary) {
            [self setTempPlayerList:list];
            break;
        }
    }

}

@end
