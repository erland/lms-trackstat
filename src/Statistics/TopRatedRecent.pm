#         TrackStat::Statistics::TopRatedRecent module
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
# 
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


use strict;
use warnings;
                   
package Plugins::TrackStat::Statistics::TopRatedRecent;

use Date::Parse qw(str2time);
use Fcntl ':flock'; # import LOCK_* constants
use File::Spec::Functions qw(:ALL);
use File::Basename;
use XML::Parser;
use DBI qw(:sql_types);
use Class::Struct;
use FindBin qw($Bin);
use POSIX qw(strftime ceil);
use Slim::Utils::Strings qw(string);
use Plugins::TrackStat::Statistics::Base;
use Slim::Utils::Prefs;

my $prefs = preferences("plugin.trackstat");
my $serverPrefs = preferences("server");


if ($] > 5.007) {
	require Encode;
}

my $driver;
my $distinct = '';

sub init {
	$driver = $serverPrefs->get('dbsource');
    $driver =~ s/dbi:(.*?):(.*)$/$1/;
    
	if(UNIVERSAL::can("Slim::Schema","sourceInformation")) {
		my ($source,$username,$password);
		($driver,$source,$username,$password) = Slim::Schema->sourceInformation;
	}

    if($driver eq 'mysql') {
    	$distinct = 'distinct';
    }
}

sub getStatisticItems {
	my %statistics = (
		topratednotrecent => {
			'webfunction' => \&getTopRatedNotRecentTracksWeb,
			'playlistfunction' => \&getTopRatedNotRecentTracks,
			'id' =>  'topratednotrecent',
			'listtype' => 'track',
			'namefunction' => \&getTopRatedNotRecentTracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENT_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isTopRatedNotRecentTracksValidInContext
		},
		topratednotrecentartists => {
			'webfunction' => \&getTopRatedNotRecentArtistsWeb,
			'playlistfunction' => \&getTopRatedNotRecentArtistTracks,
			'id' =>  'topratednotrecentartists',
			'listtype' => 'artist',
			'namefunction' => \&getTopRatedNotRecentArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENT_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isTopRatedNotRecentArtistsValidInContext
		},
		topratednotrecentalbums => {
			'webfunction' => \&getTopRatedNotRecentAlbumsWeb,
			'playlistfunction' => \&getTopRatedNotRecentAlbumTracks,
			'id' =>  'topratednotrecentalbums',
			'listtype' => 'album',
			'namefunction' => \&getTopRatedNotRecentAlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENT_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isTopRatedNotRecentAlbumsValidInContext
		}
	);
	if($prefs->get("history_enabled")) {
		$statistics{topratedrecent} = {
			'webfunction' => \&getTopRatedRecentTracksWeb,
			'playlistfunction' => \&getTopRatedRecentTracks,
			'id' =>  'topratedrecent',
			'listtype' => 'track',
			'namefunction' => \&getTopRatedRecentTracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENT_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isTopRatedRecentTracksValidInContext
		};
		$statistics{topratedrecentartists} = {
			'webfunction' => \&getTopRatedRecentArtistsWeb,
			'playlistfunction' => \&getTopRatedRecentArtistTracks,
			'id' =>  'topratedrecentartists',
			'listtype' => 'artist',
			'namefunction' => \&getTopRatedRecentArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENT_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isTopRatedRecentArtistsValidInContext
		};
		$statistics{topratedrecentalbums} = {
			'webfunction' => \&getTopRatedRecentAlbumsWeb,
			'playlistfunction' => \&getTopRatedRecentAlbumTracks,
			'id' =>  'topratedrecentalbums',
			'listtype' => 'album',
			'namefunction' => \&getTopRatedRecentAlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENT_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isTopRatedRecentAlbumsValidInContext
		};
	}
	return \%statistics;
}

sub getTopRatedRecentTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT');
	}
}
sub isTopRatedRecentTracksValidInContext {
	my $params = shift;
	if(defined($params->{'artist'})) {
		return 1;
	}elsif(defined($params->{'album'})) {
		return 1;
	}elsif(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}elsif(defined($params->{'playlist'})) {
		return 1;
	}
	return 0;
}


sub getTopRatedNotRecentTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT');
	}
}

sub isTopRatedNotRecentTracksValidInContext {
	my $params = shift;
	if(defined($params->{'artist'})) {
		return 1;
	}elsif(defined($params->{'album'})) {
		return 1;
	}elsif(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}elsif(defined($params->{'playlist'})) {
		return 1;
	}
	return 0;
}

sub getTopRatedRecentTracksWeb {
	my $params = shift;
	my $listLength = shift;
	getTopRatedHistoryTracksWeb($params,$listLength,">",getRecentTime());
    my %currentstatisticlinks = (
    	'album' => 'topratedrecent',
    	'artist' => 'topratedrecentalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getTopRatedRecentTracks {
	my $client = shift;
	my $listLength = shift;
	my $limit = shift;
	return getTopRatedHistoryTracks($client, $listLength,$limit,">",getRecentTime());
}

sub getTopRatedRecentAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTALBUMS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTALBUMS');
	}
}
sub isTopRatedRecentAlbumsValidInContext {
	my $params = shift;
	if(defined($params->{'artist'})) {
		return 1;
	}elsif(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}elsif(defined($params->{'playlist'})) {
		return 1;
	}
	return 0;
}


sub getTopRatedNotRecentAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTALBUMS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTALBUMS');
	}
}
sub isTopRatedNotRecentAlbumsValidInContext {
	my $params = shift;
	if(defined($params->{'artist'})) {
		return 1;
	}elsif(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}elsif(defined($params->{'playlist'})) {
		return 1;
	}
	return 0;
}

sub getTopRatedRecentAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getTopRatedHistoryAlbumsWeb($params,$listLength,">",getRecentTime());
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'topratedrecent',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'album' => 'topratedrecent',
    	'artist' => 'topratedrecentalbums',
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getTopRatedRecentAlbumTracks {
	my $client = shift;
	my $listLength = shift;
	my $limit = undef;
	return getTopRatedHistoryAlbumTracks($client, $listLength,$limit,">",getRecentTime());
}


sub getTopRatedRecentArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTARTISTS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTARTISTS');
	}
}
sub isTopRatedRecentArtistsValidInContext {
	my $params = shift;
	if(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}elsif(defined($params->{'playlist'})) {
		return 1;
	}
	return 0;
}


sub getTopRatedNotRecentArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTARTISTS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTARTISTS');
	}
}
sub isTopRatedNotRecentArtistsValidInContext {
	my $params = shift;
	if(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}elsif(defined($params->{'playlist'})) {
		return 1;
	}
	return 0;
}


sub getTopRatedRecentArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getTopRatedHistoryArtistsWeb($params,$listLength,">",getRecentTime());
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'topratedrecent',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'topratedrecentalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTALBUMS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'artist' => 'topratedrecentalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getTopRatedRecentArtistTracks {
	my $client = shift;
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	return getTopRatedHistoryArtistTracks($client,$listLength,$limit,">",getRecentTime());
}

sub getTopRatedNotRecentTracksWeb {
	my $params = shift;
	my $listLength = shift;
	getTopRatedHistoryTracksWeb($params,$listLength,"<",getRecentTime());
    my %currentstatisticlinks = (
    	'album' => 'topratednotrecent',
    	'artist' => 'topratednotrecentalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getTopRatedNotRecentTracks {
	my $client = shift;
	my $listLength = shift;
	my $limit = shift;
	return getTopRatedHistoryTracks($client,$listLength,$limit,"<",getRecentTime());
}

sub getTopRatedNotRecentAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getTopRatedHistoryAlbumsWeb($params,$listLength,"<",getRecentTime());
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'topratednotrecent',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'album' => 'topratednotrecent',
    	'artist' => 'topratednotrecentalbums',
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getTopRatedNotRecentAlbumTracks {
	my $client = shift;
	my $listLength = shift;
	my $limit = undef;
	return getTopRatedHistoryAlbumTracks($client,$listLength,$limit,"<",getRecentTime());
}

sub getTopRatedNotRecentArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getTopRatedHistoryArtistsWeb($params,$listLength,"<",getRecentTime());
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'topratednotrecent',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'topratednotrecentalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTALBUMS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'artist' => 'topratednotrecentalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getTopRatedNotRecentArtistTracks {
	my $client = shift;
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	return getTopRatedHistoryArtistTracks($client,$listLength,$limit,"<",getRecentTime());
}

sub getTopRatedHistoryTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select tracks.id,count(tracks.url) as sumcount,0 as added,max(track_history.played) as lastPlayed,avg(track_statistics.rating) as avgrating from tracks, track_history,contributor_track,track_statistics where tracks.urlmd5 = track_history.urlmd5 and tracks.urlmd5=track_statistics.urlmd5 and tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributor_track.contributor=$artist and tracks.audio=1 and played$beforeAfter$beforeAfterTime and track_statistics.rating is not null group by tracks.id order by avgrating desc,sumcount desc,$orderBy limit $listLength;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributor_track.contributor=$artist left join track_statistics on tracks.urlmd5 = track_statistics.urlmd5 where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) and track_statistics.rating is not null group by tracks.id order by track_statistics.rating desc,track_statistics.playCount desc,$orderBy limit $listLength;";
	    }
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'album'})) {
		my $album = $params->{'album'};
	    $sql = "select tracks.id,count(tracks.url) as sumcount,0 as added,max(track_history.played) as lastPlayed,avg(track_statistics.rating) as avgrating from tracks, track_history,track_statistics where tracks.urlmd5 = track_history.urlmd5 and tracks.urlmd5=track_statistics.urlmd5 and tracks.album=$album and tracks.audio=1 and played$beforeAfter$beforeAfterTime and track_statistics.rating is not null group by tracks.id order by avgrating desc,sumcount desc,$orderBy;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.urlmd5 = track_statistics.urlmd5 where tracks.album=$album and tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) and track_statistics.rating is not null order by track_statistics.rating desc,track_statistics.playCount desc,$orderBy;";
	    }
	    $params->{'statisticparameters'} = "&album=$album";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select tracks.id,count(tracks.url) as sumcount,0 as added,max(track_history.played) as lastPlayed,avg(track_statistics.rating) as avgrating from tracks, track_history,genre_track,track_statistics where tracks.urlmd5 = track_history.urlmd5 and tracks.urlmd5=track_statistics.urlmd5 and tracks.id=genre_track.track and genre_track.genre=$genre and tracks.audio=1 and played$beforeAfter$beforeAfterTime and track_statistics.rating is not null group by tracks.id order by avgrating desc,sumcount desc,$orderBy limit $listLength;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.urlmd5 = track_statistics.urlmd5 where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) and track_statistics.rating is not null group by tracks.id order by track_statistics.rating desc,track_statistics.playCount desc,$orderBy limit $listLength;";
	    }
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select tracks.id,count(tracks.url) as sumcount,0 as added,max(track_history.played) as lastPlayed,avg(track_statistics.rating) as avgrating from tracks, track_history, track_statistics where tracks.urlmd5 = track_history.urlmd5 and tracks.urlmd5=track_statistics.urlmd5 and tracks.year=$year and tracks.audio=1 and played$beforeAfter$beforeAfterTime and track_statistics.rating is not null group by tracks.id order by avgrating desc,sumcount desc,$orderBy limit $listLength;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.urlmd5 = track_statistics.urlmd5 where tracks.year=$year and tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) and track_statistics.rating is not null order by track_statistics.rating desc,track_statistics.playCount desc,$orderBy limit $listLength;";
	    }
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select tracks.id,count(tracks.url) as sumcount,0 as added,max(track_history.played) as lastPlayed,avg(track_statistics.rating) as avgrating from tracks, track_history,playlist_track, track_statistics where tracks.urlmd5 = track_history.urlmd5 and tracks.urlmd5=track_statistics.urlmd5 and tracks.url=playlist_track.track and playlist_track.playlist=$playlist and tracks.audio=1 and played$beforeAfter$beforeAfterTime and track_statistics.rating is not null group by tracks.id order by avgrating desc,sumcount desc,$orderBy limit $listLength;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join playlist_track on tracks.url=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.urlmd5 = track_statistics.urlmd5 where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) and track_statistics.rating is not null order by track_statistics.rating desc,track_statistics.playCount desc,$orderBy limit $listLength;";
	    }
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select tracks.id,count(tracks.url) as sumcount,0 as added,max(track_history.played) as lastPlayed,avg(track_statistics.rating) as avgrating from tracks, track_history, track_statistics where tracks.urlmd5 = track_history.urlmd5 and tracks.urlmd5=track_statistics.urlmd5 and tracks.audio=1 and played$beforeAfter$beforeAfterTime and track_statistics.rating is not null group by tracks.id order by avgrating desc,sumcount desc,$orderBy limit $listLength;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.urlmd5 = track_statistics.urlmd5 where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) and track_statistics.rating is not null order by track_statistics.rating desc,track_statistics.playCount desc,$orderBy limit $listLength;";
	    }
	}
    Plugins::TrackStat::Statistics::Base::getTracksWeb($sql,$params);
}

sub getTopRatedHistoryTracks {
	my $client = shift;
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		my $clientid = $client->id;
		$sql = "select tracks.id,count(tracks.url) as sumcount,0 as added,max(track_history.played) as lastPlayed,avg(track_statistics.rating) as avgrating from tracks join track_history on tracks.urlmd5=track_history.urlmd5 join track_statistics on tracks.urlmd5=track_statistics.urlmd5 left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id and dynamicplaylist_history.client='$clientid' where tracks.audio=1 and dynamicplaylist_history.id is null and played$beforeAfter$beforeAfterTime and track_statistics.rating is not null group by tracks.id order by avgrating desc,sumcount desc,$orderBy limit $listLength;";
		if($beforeAfter eq "<") {
			$sql = "select tracks.id from tracks left join track_statistics on tracks.urlmd5 = track_statistics.urlmd5 left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id and dynamicplaylist_history.client='$clientid' where tracks.audio=1 and dynamicplaylist_history.id is null and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) and track_statistics.rating is not null order by track_statistics.rating desc,track_statistics.playCount desc,$orderBy limit $listLength;";
		}
	}else {
		$sql = "select tracks.id,count(tracks.url) as sumcount,0 as added,max(track_history.played) as lastPlayed,avg(track_statistics.rating) as avgrating from tracks, track_history, track_statistics where tracks.urlmd5 = track_history.urlmd5 and tracks.urlmd5=track_statistics.urlmd5 and tracks.audio=1 and played$beforeAfter$beforeAfterTime and track_statistics.rating is not null group by tracks.id order by avgrating desc,sumcount desc,$orderBy limit $listLength;";
		if($beforeAfter eq "<") {
			$sql = "select tracks.id from tracks left join track_statistics on tracks.urlmd5 = track_statistics.urlmd5 where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) and track_statistics.rating is not null order by track_statistics.rating desc,track_statistics.playCount desc,$orderBy limit $listLength;";
		}
	}
    return Plugins::TrackStat::Statistics::Base::getTracks($sql,$limit);
}

sub getTopRatedHistoryAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,contributor_track, track_statistics where tracks.urlmd5=track_history.urlmd5 and tracks.urlmd5=track_statistics.urlmd5 and tracks.album=albums.id and tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributor_track.contributor=$artist and played$beforeAfter$beforeAfterTime group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributor_track.contributor=$artist left join track_statistics on tracks.urlmd5 = track_statistics.urlmd5 join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,genre_track,track_statistics where tracks.urlmd5=track_history.urlmd5 and tracks.urlmd5=track_statistics.urlmd5 and tracks.album=albums.id and tracks.id=genre_track.track and genre_track.genre=$genre and played$beforeAfter$beforeAfterTime group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.urlmd5 = track_statistics.urlmd5 join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums, track_statistics where tracks.urlmd5=track_history.urlmd5 and tracks.urlmd5=track_statistics.urlmd5 and tracks.album=albums.id and tracks.year=$year and played$beforeAfter$beforeAfterTime group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.urlmd5 = track_statistics.urlmd5 join albums on tracks.album=albums.id where tracks.year=$year group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,playlist_track,track_statistics where tracks.urlmd5=track_history.urlmd5 and tracks.urlmd5=track_statistics.urlmd5 and tracks.album=albums.id and tracks.url=playlist_track.track and playlist_track.playlist=$playlist and played$beforeAfter$beforeAfterTime group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join playlist_track on tracks.url=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.urlmd5 = track_statistics.urlmd5 join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums, track_statistics where tracks.urlmd5=track_history.urlmd5 and tracks.urlmd5=track_statistics.urlmd5 and tracks.album=albums.id and played$beforeAfter$beforeAfterTime group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.urlmd5 = track_statistics.urlmd5 join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    }
	}
    Plugins::TrackStat::Statistics::Base::getAlbumsWeb($sql,$params);
}

sub getTopRatedHistoryAlbumTracks {
	my $client = shift;
	my $listLength = shift;
	my $limit = shift;
	$limit = undef;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		my $clientid = $client->id;
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks join track_history on tracks.urlmd5=track_history.urlmd5 join albums on tracks.album=albums.id join track_statistics on tracks.urlmd5=track_statistics.urlmd5 left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id and dynamicplaylist_history.client='$clientid' where dynamicplaylist_history.id is null and played$beforeAfter$beforeAfterTime group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
		if($beforeAfter eq "<") {
			$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.urlmd5 = track_statistics.urlmd5 join albums on tracks.album=albums.id left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id and dynamicplaylist_history.client='$clientid' where dynamicplaylist_history.id is null group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,avgcount desc,$orderBy limit $listLength";
		}
	}else {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums, track_statistics where tracks.urlmd5=track_history.urlmd5 and tracks.urlmd5=track_statistics.urlmd5 and tracks.album=albums.id and played$beforeAfter$beforeAfterTime group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
		if($beforeAfter eq "<") {
			$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.urlmd5 = track_statistics.urlmd5 join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,avgcount desc,$orderBy limit $listLength";
		}
	}
    return Plugins::TrackStat::Statistics::Base::getAlbumTracks($client,$sql,$limit);
}

sub getTopRatedHistoryArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors,genre_track,track_statistics where tracks.urlmd5 = track_history.urlmd5 and tracks.urlmd5=track_statistics.urlmd5 and tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributors.id = contributor_track.contributor and tracks.id=genre_track.track and genre_track.genre=$genre and played$beforeAfter$beforeAfterTime group by contributors.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.urlmd5 = track_statistics.urlmd5 join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,sumcount desc,$orderBy limit $listLength";    
		}
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors,track_statistics where tracks.urlmd5 = track_history.urlmd5 and tracks.urlmd5=track_statistics.urlmd5 and tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributors.id = contributor_track.contributor and tracks.year=$year and played$beforeAfter$beforeAfterTime group by contributors.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.urlmd5 = track_statistics.urlmd5 join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor where tracks.year=$year group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,sumcount desc,$orderBy limit $listLength";    
		}
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors,playlist_track,track_statistics where tracks.urlmd5 = track_history.urlmd5 and tracks.urlmd5=track_statistics.urlmd5 and tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributors.id = contributor_track.contributor and tracks.url=playlist_track.track and playlist_track.playlist=$playlist and played$beforeAfter$beforeAfterTime group by contributors.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join playlist_track on tracks.url=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.urlmd5 = track_statistics.urlmd5 join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,sumcount desc,$orderBy limit $listLength";    
		}
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors,track_statistics where tracks.urlmd5 = track_history.urlmd5 and tracks.urlmd5=track_statistics.urlmd5 and tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributors.id = contributor_track.contributor and played$beforeAfter$beforeAfterTime group by contributors.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.urlmd5 = track_statistics.urlmd5 join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,sumcount desc,$orderBy limit $listLength";    
		}
	}
    Plugins::TrackStat::Statistics::Base::getArtistsWeb($sql,$params);
}

sub getTopRatedHistoryArtistTracks {
	my $client = shift;
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	$limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		my $clientid = $client->id;
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks join track_history on tracks.urlmd5=track_history.urlmd5 join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributor_track.contributor=contributors.id join track_statistics on tracks.urlmd5=track_statistics.urlmd5 left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id and dynamicplaylist_history.client='$clientid' where dynamicplaylist_history.id is null and played$beforeAfter$beforeAfterTime group by contributors.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
		if($beforeAfter eq "<") {
			$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.urlmd5 = track_statistics.urlmd5 join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id and dynamicplaylist_history.client='$clientid' where dynamicplaylist_history.id is null group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,sumcount desc,$orderBy limit $listLength";    
		}
	}else {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors,track_statistics where tracks.urlmd5 = track_history.urlmd5 and tracks.urlmd5=track_statistics.urlmd5 and tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributors.id = contributor_track.contributor and played$beforeAfter$beforeAfterTime group by contributors.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
		if($beforeAfter eq "<") {
			$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.urlmd5 = track_statistics.urlmd5 join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,sumcount desc,$orderBy limit $listLength";    
		}
	}
    return Plugins::TrackStat::Statistics::Base::getArtistTracks($client,$sql,$limit);
}

sub getRecentTime() {
	my $days = $prefs->get("recent_number_of_days");
	if(!defined($days)) {
		$days = 30;
	}
	return time() - 24*3600*$days;
}


1;

__END__
