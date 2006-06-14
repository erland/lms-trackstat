#         TrackStat::Statistics::LeastPlayedRecentAdded module
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
                   
package Plugins::TrackStat::Statistics::LeastPlayedRecentAdded;

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


if ($] > 5.007) {
	require Encode;
}

my $driver;
my $distinct = '';

sub init {
	$driver = Slim::Utils::Prefs::get('dbsource');
    $driver =~ s/dbi:(.*?):(.*)$/$1/;
    
    if($driver eq 'mysql') {
    	$distinct = 'distinct';
    }
}

sub getStatisticItems {
	my %statistics = (
		leastplayedrecentadded => {
			'webfunction' => \&getLeastPlayedRecentAddedTracksWeb,
			'playlistfunction' => \&getLeastPlayedRecentAddedTracks,
			'id' =>  'leastplayedrecentadded',
			'namefunction' => \&getLeastPlayedRecentAddedTracksName,
			'contextfunction' => \&isLeastPlayedRecentAddedTracksValidInContext
		},
		leastplayedrecentaddedartists => {
			'webfunction' => \&getLeastPlayedRecentAddedArtistsWeb,
			'playlistfunction' => \&getLeastPlayedRecentAddedArtistTracks,
			'id' =>  'leastplayedrecentaddedartists',
			'namefunction' => \&getLeastPlayedRecentAddedArtistsName,
			'contextfunction' => \&isLeastPlayedRecentAddedArtistsValidInContext
		},
		leastplayedrecentaddedalbums => {
			'webfunction' => \&getLeastPlayedRecentAddedAlbumsWeb,
			'playlistfunction' => \&getLeastPlayedRecentAddedAlbumTracks,
			'id' =>  'leastplayedrecentaddedalbums',
			'namefunction' => \&getLeastPlayedRecentAddedAlbumsName,
			'contextfunction' => \&isLeastPlayedRecentAddedAlbumsValidInContext
		},
		leastplayednotrecentadded => {
			'webfunction' => \&getLeastPlayedNotRecentAddedTracksWeb,
			'playlistfunction' => \&getLeastPlayedNotRecentAddedTracks,
			'id' =>  'leastplayednotrecentadded',
			'namefunction' => \&getLeastPlayedNotRecentAddedTracksName,
			'contextfunction' => \&isLeastPlayedNotRecentAddedTracksValidInContext
		},
		leastplayednotrecentaddedartists => {
			'webfunction' => \&getLeastPlayedNotRecentAddedArtistsWeb,
			'playlistfunction' => \&getLeastPlayedNotRecentAddedArtistTracks,
			'id' =>  'leastplayednotrecentaddedartists',
			'namefunction' => \&getLeastPlayedNotRecentAddedArtistsName,
			'contextfunction' => \&isLeastPlayedNotRecentAddedArtistsValidInContext
		},
		leastplayednotrecentaddedalbums => {
			'webfunction' => \&getLeastPlayedNotRecentAddedAlbumsWeb,
			'playlistfunction' => \&getLeastPlayedNotRecentAddedAlbumTracks,
			'id' =>  'leastplayednotrecentaddedalbums',
			'namefunction' => \&getLeastPlayedNotRecentAddedAlbumsName,
			'contextfunction' => \&isLeastPlayedNotRecentAddedAlbumsValidInContext
		}
	);
	return \%statistics;
}

sub getLeastPlayedRecentAddedTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_FORYEAR')." ".$year;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED');
	}
}

sub isLeastPlayedRecentAddedTracksValidInContext {
	my $params = shift;
	if(defined($params->{'artist'})) {
		return 1;
	}elsif(defined($params->{'album'})) {
		return 1;
	}elsif(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}
	return 0;
}

sub getLeastPlayedRecentAddedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $recentaddedcmp = shift;
	if(!defined($recentaddedcmp)) {
		$recentaddedcmp = '>';
	}
	my $recentadded = getRecentAddedTime();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded group by tracks.url order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks, track_statistics, contributor_track where tracks.url = track_statistics.url and tracks.id=contributor_track.track and contributor_track.contributor=$artist and tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded group by tracks.url order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
	    }
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'album'})) {
		my $album = $params->{'album'};
	    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and tracks.album=$album and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount asc,tracks.playCount asc,$orderBy;";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks, track_statistics where tracks.url = track_statistics.url and tracks.audio=1 and tracks.album=$album and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount asc,tracks.playCount asc,$orderBy;";
	    }
	    $params->{'statisticparameters'} = "&album=$album";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks, track_statistics, genre_track where tracks.url = track_statistics.url and tracks.id=genre_track.track and genre_track.genre=$genre and tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
	    }
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.year=$year and tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks, track_statistics where tracks.url = track_statistics.url and tracks.year=$year and tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
	    }
	    $params->{'statisticparameters'} = "&year=$year";
	}else {
	    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks, track_statistics where tracks.url = track_statistics.url and tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
	    }
	}
    Plugins::TrackStat::Statistics::Base::getTracksWeb($sql,$params);
    if($recentaddedcmp eq '>') {
	    my %currentstatisticlinks = (
	    	'album' => 'leastplayedrecentadded',
	    	'artist' => 'leastplayedrecentaddedalbums'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}else {
	    my %currentstatisticlinks = (
	    	'album' => 'leastplayednotrecentadded',
	    	'artist' => 'leastplayednotrecentaddedalbums'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}
}

sub getLeastPlayedRecentAddedTracks {
	my $listLength = shift;
	my $limit = shift;
	my $recentaddedcmp = shift;
	if(!defined($recentaddedcmp)) {
		$recentaddedcmp = '>';
	}
	my $recentadded = getRecentAddedTime();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select tracks.url from tracks, track_statistics where tracks.url = track_statistics.url and tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
    }
    return Plugins::TrackStat::Statistics::Base::getTracks($sql,$limit);
}

sub getLeastPlayedRecentAddedAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDALBUMS_FORYEAR')." ".$year;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDALBUMS');
	}
}

sub isLeastPlayedRecentAddedAlbumsValidInContext {
	my $params = shift;
	if(defined($params->{'artist'})) {
		return 1;
	}elsif(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}
	return 0;
}

sub getLeastPlayedRecentAddedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $recentaddedcmp = shift;
	if(!defined($recentaddedcmp)) {
		$recentaddedcmp = '>';
	}
	my $recentadded = getRecentAddedTime();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount asc,avgrating asc,$orderBy limit $listLength";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks, track_statistics,albums,contributor_track where tracks.url = track_statistics.url and tracks.album=albums.id and tracks.id=contributor_track.track and contributor_track.contributor=$artist group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount asc,avgrating asc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount asc,avgrating asc,$orderBy limit $listLength";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks, track_statistics,albums,genre_track where tracks.url = track_statistics.url and tracks.album=albums.id and tracks.id=genre_track.track and genre_track.genre=$genre group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount asc,avgrating asc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id where tracks.year=$year group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount asc,avgrating asc,$orderBy limit $listLength";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks, track_statistics,albums where tracks.url = track_statistics.url and tracks.album=albums.id and tracks.year=$year group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount asc,avgrating asc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&year=$year";
	}else {
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount asc,avgrating asc,$orderBy limit $listLength";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks, track_statistics,albums where tracks.url = track_statistics.url and tracks.album=albums.id group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount asc,avgrating asc,$orderBy limit $listLength";
	    }
	}
    Plugins::TrackStat::Statistics::Base::getAlbumsWeb($sql,$params);
    if($recentaddedcmp eq '>') {
	    my @statisticlinks = ();
	    push @statisticlinks, {
	    	'id' => 'leastplayedrecentadded',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_FORALBUM_SHORT')
	    };
	    $params->{'substatisticitems'} = \@statisticlinks;
	    my %currentstatisticlinks = (
	    	'album' => 'leastplayedrecentadded'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}else {
	    my @statisticlinks = ();
	    push @statisticlinks, {
	    	'id' => 'leastplayednotrecentadded',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_FORALBUM_SHORT')
	    };
	    $params->{'substatisticitems'} = \@statisticlinks;
	    my %currentstatisticlinks = (
	    	'album' => 'leastplayednotrecentadded'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}
}

sub getLeastPlayedRecentAddedAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	my $recentaddedcmp = shift;
	if(!defined($recentaddedcmp)) {
		$recentaddedcmp = '>';
	}
	my $recentadded = getRecentAddedTime();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount asc,avgrating asc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks, track_statistics,albums where tracks.url = track_statistics.url and tracks.album=albums.id group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount asc,avgrating asc,$orderBy limit $listLength";
    }
    return Plugins::TrackStat::Statistics::Base::getAlbumTracks($sql,$limit);
}

sub getLeastPlayedRecentAddedArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDARTISTS_FORYEAR')." ".$year;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDARTISTS');
	}
}

sub isLeastPlayedRecentAddedArtistsValidInContext {
	my $params = shift;
	if(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}
	return 0;
}

sub getLeastPlayedRecentAddedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $recentaddedcmp = shift;
	if(!defined($recentaddedcmp)) {
		$recentaddedcmp = '>';
	}
	my $recentadded = getRecentAddedTime();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by sumcount asc,avgrating asc,$orderBy limit $listLength";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks , track_statistics , contributors, contributor_track, genre_track where tracks.url = track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and tracks.id=genre_track.track and genre_track.genre=$genre group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by sumcount asc,avgrating asc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor where tracks.year=$year group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by sumcount asc,avgrating asc,$orderBy limit $listLength";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks , track_statistics , contributors, contributor_track where tracks.url = track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and tracks.year=$year group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by sumcount asc,avgrating asc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&year=$year";
	}else {
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by sumcount asc,avgrating asc,$orderBy limit $listLength";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks , track_statistics , contributors, contributor_track where tracks.url = track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by sumcount asc,avgrating asc,$orderBy limit $listLength";
	    }
	}
    Plugins::TrackStat::Statistics::Base::getArtistsWeb($sql,$params);
    if($recentaddedcmp eq '>') {
	    my @statisticlinks = ();
	    push @statisticlinks, {
	    	'id' => 'leastplayedrecentadded',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_FORARTIST_SHORT')
	    };
	    push @statisticlinks, {
	    	'id' => 'leastplayedrecentaddedalbums',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDALBUMS_FORARTIST_SHORT')
	    };
	    $params->{'substatisticitems'} = \@statisticlinks;
	    my %currentstatisticlinks = (
	    	'artist' => 'leastplayedrecentaddedalbums'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}else {
	    my @statisticlinks = ();
	    push @statisticlinks, {
	    	'id' => 'leastplayednotrecentadded',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_FORARTIST_SHORT')
	    };
	    push @statisticlinks, {
	    	'id' => 'leastplayednotrecentaddedalbums',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDALBUMS_FORARTIST_SHORT')
	    };
	    $params->{'substatisticitems'} = \@statisticlinks;
	    my %currentstatisticlinks = (
	    	'artist' => 'leastplayednotrecentaddedalbums'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}
}

sub getLeastPlayedRecentAddedArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	my $recentaddedcmp = shift;
	if(!defined($recentaddedcmp)) {
		$recentaddedcmp = '>';
	}
	my $recentadded = getRecentAddedTime();
	$limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by sumcount asc,avgrating asc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks , track_statistics , contributors, contributor_track where tracks.url = track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by sumcount asc,avgrating asc,$orderBy limit $listLength";
    }
    return Plugins::TrackStat::Statistics::Base::getArtistTracks($sql,$limit);
}

sub getLeastPlayedNotRecentAddedTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_FORYEAR')." ".$year;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED');
	}
}

sub isLeastPlayedNotRecentAddedTracksValidInContext {
	my $params = shift;
	if(defined($params->{'artist'})) {
		return 1;
	}elsif(defined($params->{'album'})) {
		return 1;
	}elsif(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}
	return 0;
}

sub getLeastPlayedNotRecentAddedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	getLeastPlayedRecentAddedTracksWeb($params,$listLength,'<');
}

sub getLeastPlayedNotRecentAddedTracks {
	my $listLength = shift;
	my $limit = shift;
	return getLeastPlayedRecentAddedTracks($listLength,$limit,'<');
}

sub getLeastPlayedNotRecentAddedAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDALBUMS_FORYEAR')." ".$year;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDALBUMS');
	}
}

sub isLeastPlayedNotRecentAddedAlbumsValidInContext {
	my $params = shift;
	if(defined($params->{'artist'})) {
		return 1;
	}elsif(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}
	return 0;
}

sub getLeastPlayedNotRecentAddedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getLeastPlayedRecentAddedAlbumsWeb($params,$listLength,'<');
}

sub getLeastPlayedNotRecentAddedAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	return getLeastPlayedRecentAddedAlbumTracks($listLength,$limit,'<');
}

sub getLeastPlayedNotRecentAddedArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDARTISTS_FORYEAR')." ".$year;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDARTISTS');
	}
}

sub isLeastPlayedNotRecentAddedArtistsValidInContext {
	my $params = shift;
	if(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}
	return 0;
}

sub getLeastPlayedNotRecentAddedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getLeastPlayedRecentAddedArtistsWeb($params,$listLength,'<');
}

sub getLeastPlayedNotRecentAddedArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	return getLeastPlayedRecentAddedArtistTracks($listLength,$limit,'<');
}

sub getRecentAddedTime() {
	my $days = Slim::Utils::Prefs::get("plugin_trackstat_recentadded_number_of_days");
	if(!defined($days)) {
		$days = 30;
	}
	return time() - 24*3600*$days;
}

sub strings()
{
	return "
PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED
	EN	Least played songs recently added

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_FORARTIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_FORARTIST
	EN	Least played songs recently added by: 

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_FORALBUM_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_FORALBUM
	EN	Least played songs recently added from: 

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_FORGENRE_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_FORGENRE
	EN	Least played songs recently added in: 

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_FORYEAR_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_FORYEAR
	EN	Least played songs recently added from: 

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDALBUMS
	EN	Least played albums recently added

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDALBUMS_FORARTIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDALBUMS_FORARTIST
	EN	Least played albums recently added by: 

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDALBUMS_FORGENRE_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDALBUMS_FORGENRE
	EN	Least played albums recently added in: 

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDALBUMS_FORYEAR_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDALBUMS_FORYEAR
	EN	Least played albums recently added from: 

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDARTISTS
	EN	Least played artists recently added

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDARTISTS_FORGENRE_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDARTISTS_FORGENRE
	EN	Least played artists recently added in: 

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDARTISTS_FORYEAR_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDARTISTS_FORYEAR
	EN	Least played artists recently added from: 

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED
	EN	Least played songs not recently added

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_FORARTIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_FORARTIST
	EN	Least played songs not recently added by: 

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_FORALBUM_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_FORALBUM
	EN	Least played songs not recently added from: 

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_FORGENRE_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_FORGENRE
	EN	Least played songs not recently added in: 

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_FORYEAR_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_FORYEAR
	EN	Least played songs not recently added from: 

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDALBUMS
	EN	Least played albums not recently added

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDALBUMS_FORARTIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDALBUMS_FORARTIST
	EN	Least played albums not recently added by: 

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDALBUMS_FORGENRE_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDALBUMS_FORGENRE
	EN	Least played albums not recently added in: 

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDALBUMS_FORYEAR_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDALBUMS_FORYEAR
	EN	Least played albums not recently added from: 

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDARTISTS
	EN	Least played artists not recently added

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDARTISTS_FORGENRE_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDARTISTS_FORGENRE
	EN	Least played artists not recently added in: 

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDARTISTS_FORYEAR_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDARTISTS_FORYEAR
	EN	Least played artists not recently added from: 
";
}

1;

__END__
