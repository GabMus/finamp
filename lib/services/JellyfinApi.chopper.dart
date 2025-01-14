// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'JellyfinApi.dart';

// **************************************************************************
// ChopperGenerator
// **************************************************************************

// ignore_for_file: always_put_control_body_on_new_line, always_specify_types, prefer_const_declarations
class _$JellyfinApi extends JellyfinApi {
  _$JellyfinApi([ChopperClient client]) {
    if (client == null) return;
    this.client = client;
  }

  @override
  final definitionType = JellyfinApi;

  @override
  Future<dynamic> getPublicUsers() {
    final $url = '/Users/Public';
    final $request = Request('GET', $url, client.baseUrl);
    return client.send($request);
  }

  @override
  Future<dynamic> authenticateViaName(Map<String, String> usernameAndPassword) {
    final $url = '/Users/AuthenticateByName';
    final $body = usernameAndPassword;
    final $request = Request('POST', $url, client.baseUrl, body: $body);
    return client.send($request);
  }

  @override
  Future<dynamic> getAlbumPrimaryImage({String id, String format}) {
    final $url = '/Items/$id/Images/Primary';
    final $params = <String, dynamic>{'format': format};
    final $request = Request('GET', $url, client.baseUrl, parameters: $params);
    return client.send($request);
  }

  @override
  Future<dynamic> getViews(String id) {
    final $url = '/Users/$id/Views';
    final $request = Request('GET', $url, client.baseUrl);
    return client.send($request);
  }

  @override
  Future<dynamic> getItems(
      {String userId,
      String includeItemTypes,
      String parentId,
      String albumArtistIds,
      bool recursive,
      String sortBy,
      String fields = defaultFields,
      String searchTerm}) {
    final $url = '/Users/$userId/Items';
    final $params = <String, dynamic>{
      'IncludeItemTypes': includeItemTypes,
      'ParentId': parentId,
      'AlbumArtistIds': albumArtistIds,
      'Recursive': recursive,
      'SortBy': sortBy,
      'Fields': fields,
      'searchTerm': searchTerm
    };
    final $request = Request('GET', $url, client.baseUrl, parameters: $params);
    return client.send($request);
  }

  @override
  Future<dynamic> getPlaybackInfo({String id, String userId}) {
    final $url = '/Items/$id/PlaybackInfo';
    final $params = <String, dynamic>{'userId': userId};
    final $request = Request('GET', $url, client.baseUrl, parameters: $params);
    return client.send($request);
  }

  @override
  Future<dynamic> startPlayback(PlaybackProgressInfo playbackProgressInfo) {
    final $url = '/Sessions/Playing';
    final $body = playbackProgressInfo;
    final $request = Request('POST', $url, client.baseUrl, body: $body);
    return client.send($request);
  }

  @override
  Future<dynamic> playbackStatusUpdate(
      PlaybackProgressInfo playbackProgressInfo) {
    final $url = '/Sessions/Playing/Progress';
    final $body = playbackProgressInfo;
    final $request = Request('POST', $url, client.baseUrl, body: $body);
    return client.send($request);
  }

  @override
  Future<dynamic> playbackStatusStopped(
      PlaybackProgressInfo playbackProgressInfo) {
    final $url = '/Sessions/Playing/Stopped';
    final $body = playbackProgressInfo;
    final $request = Request('POST', $url, client.baseUrl, body: $body);
    return client.send($request);
  }

  @override
  Future<dynamic> getPlaylistItems(
      {String playlistId,
      String userId,
      String includeItemTypes,
      String parentId,
      bool recursive,
      String sortBy,
      String fields = defaultFields}) {
    final $url = '/Playlists/$playlistId/Items';
    final $params = <String, dynamic>{
      'UserId': userId,
      'IncludeItemTypes': includeItemTypes,
      'ParentId': parentId,
      'Recursive': recursive,
      'SortBy': sortBy,
      'Fields': fields
    };
    final $request = Request('GET', $url, client.baseUrl, parameters: $params);
    return client.send($request);
  }

  @override
  Future<dynamic> getAlbumArtists(
      {String includeItemTypes,
      String parentId,
      bool recursive,
      String sortBy,
      String fields = "parentId,indexNumber,songCount",
      String searchTerm}) {
    final $url = '/Artists/AlbumArtists';
    final $params = <String, dynamic>{
      'IncludeItemTypes': includeItemTypes,
      'ParentId': parentId,
      'Recursive': recursive,
      'SortBy': sortBy,
      'Fields': fields,
      'searchTerm': searchTerm
    };
    final $request = Request('GET', $url, client.baseUrl, parameters: $params);
    return client.send($request);
  }
}
