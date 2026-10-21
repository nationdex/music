import 'dart:convert';

import 'package:http/http.dart' as http;

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> innertubeJson(
  List<(String id, String title, String channel, String? length)> videos,
) => {
  'contents': {
    'twoColumnSearchResultsRenderer': {
      'primaryContents': {
        'sectionListRenderer': {
          'contents': [
            {
              'itemSectionRenderer': {
                'contents': [
                  {'adSlotRenderer': {}},
                  for (final v in videos)
                    {
                      'videoRenderer': {
                        'videoId': v.$1,
                        'title': {
                          'runs': [
                            {'text': v.$2},
                          ],
                        },
                        'ownerText': {
                          'runs': [
                            {'text': v.$3},
                          ],
                        },
                        'lengthText': v.$4 == null
                            ? null
                            : {'simpleText': v.$4},
                      },
                    },
                ],
              },
            },
          ],
        },
      },
    },
  },
};
