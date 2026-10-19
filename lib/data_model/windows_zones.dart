// Windows time zone IDs and the tzdata zones they stand for, from the Unicode
// CLDR's windowsZones.xml. Zones carry the names tzdata's zone.tab lists, such
// as Asia/Kolkata where CLDR keeps Asia/Calcutta.
//
// UNICODE LICENSE V3
//
// COPYRIGHT AND PERMISSION NOTICE
//
// Copyright © 1991-2025 Unicode, Inc.
//
// NOTICE TO USER: Carefully read the following legal agreement. BY
// DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR
// SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE
// TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
// DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of data files and any associated documentation (the "Data Files") or
// software and any associated documentation (the "Software") to deal in the
// Data Files or Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, and/or sell
// copies of the Data Files or Software, and to permit persons to whom the
// Data Files or Software are furnished to do so, provided that either (a)
// this copyright and permission notice appear with all copies of the Data
// Files or Software, or (b) this copyright and permission notice appear in
// associated Documentation.
//
// THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
// KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
// THIRD PARTY RIGHTS.
//
// IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
// BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
// OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
// WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
// ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
// FILES OR SOFTWARE.
//
// Except as contained in this notice, the name of a copyright holder shall
// not be used in advertising or otherwise to promote the sale, use or other
// dealings in these Data Files or Software without prior written
// authorization of the copyright holder.

/// Each Windows zone ID, as `tzutil /g` prints it, to its tzdata zone by
/// territory: `001` for the world, then each country whose zone differs.
///
/// The UTC±hh zones list countries only: CLDR's `001` for them is an
/// `Etc/GMT` offset, which a box does not offer. Dateline Standard Time, with
/// nothing else, is left out. So is a place whose clock no longer follows the
/// Windows zone CLDR files it under, such as Vostok, since the box would then
/// show a different time from the computer.
const windowsZones = <String, Map<String, String>>{
  'Afghanistan Standard Time': {'001': 'Asia/Kabul'},
  'Alaskan Standard Time': {'001': 'America/Anchorage'},
  'Alberta Standard Time': {'001': 'America/Edmonton'},
  'Aleutian Standard Time': {'001': 'America/Adak'},
  'Altai Standard Time': {'001': 'Asia/Barnaul'},
  'Arab Standard Time': {
    '001': 'Asia/Riyadh',
    'BH': 'Asia/Bahrain',
    'KW': 'Asia/Kuwait',
    'QA': 'Asia/Qatar',
    'YE': 'Asia/Aden',
  },
  'Arabian Standard Time': {'001': 'Asia/Dubai', 'OM': 'Asia/Muscat'},
  'Arabic Standard Time': {'001': 'Asia/Baghdad'},
  'Argentina Standard Time': {'001': 'America/Argentina/Buenos_Aires'},
  'Astrakhan Standard Time': {'001': 'Europe/Astrakhan'},
  'Atlantic Standard Time': {
    '001': 'America/Halifax',
    'BM': 'Atlantic/Bermuda',
    'GL': 'America/Thule',
  },
  'AUS Central Standard Time': {'001': 'Australia/Darwin'},
  'Aus Central W. Standard Time': {'001': 'Australia/Eucla'},
  'AUS Eastern Standard Time': {'001': 'Australia/Sydney'},
  'Azerbaijan Standard Time': {'001': 'Asia/Baku'},
  'Azores Standard Time': {'001': 'Atlantic/Azores'},
  'Bahia Standard Time': {'001': 'America/Bahia'},
  'Bangladesh Standard Time': {'001': 'Asia/Dhaka', 'BT': 'Asia/Thimphu'},
  'Belarus Standard Time': {'001': 'Europe/Minsk'},
  'Bougainville Standard Time': {'001': 'Pacific/Bougainville'},
  'British Columbia Standard Time': {'001': 'America/Vancouver'},
  'Canada Central Standard Time': {'001': 'America/Regina'},
  'Cape Verde Standard Time': {'001': 'Atlantic/Cape_Verde'},
  'Caucasus Standard Time': {'001': 'Asia/Yerevan'},
  'Cen. Australia Standard Time': {'001': 'Australia/Adelaide'},
  'Central America Standard Time': {
    '001': 'America/Guatemala',
    'BZ': 'America/Belize',
    'CR': 'America/Costa_Rica',
    'EC': 'Pacific/Galapagos',
    'HN': 'America/Tegucigalpa',
    'NI': 'America/Managua',
    'SV': 'America/El_Salvador',
  },
  'Central Asia Standard Time': {
    '001': 'Asia/Bishkek',
    'CN': 'Asia/Urumqi',
    'IO': 'Indian/Chagos',
  },
  'Central Brazilian Standard Time': {'001': 'America/Cuiaba'},
  'Central Europe Standard Time': {
    '001': 'Europe/Budapest',
    'AL': 'Europe/Tirane',
    'CZ': 'Europe/Prague',
    'ME': 'Europe/Podgorica',
    'RS': 'Europe/Belgrade',
    'SI': 'Europe/Ljubljana',
    'SK': 'Europe/Bratislava',
  },
  'Central European Standard Time': {
    '001': 'Europe/Warsaw',
    'BA': 'Europe/Sarajevo',
    'HR': 'Europe/Zagreb',
    'MK': 'Europe/Skopje',
  },
  'Central Pacific Standard Time': {
    '001': 'Pacific/Guadalcanal',
    'FM': 'Pacific/Pohnpei',
    'NC': 'Pacific/Noumea',
    'VU': 'Pacific/Efate',
  },
  'Central Standard Time': {
    '001': 'America/Chicago',
    'CA': 'America/Rankin_Inlet',
    'MX': 'America/Matamoros',
  },
  'Central Standard Time (Mexico)': {'001': 'America/Mexico_City'},
  'Chatham Islands Standard Time': {'001': 'Pacific/Chatham'},
  'China Standard Time': {
    '001': 'Asia/Shanghai',
    'HK': 'Asia/Hong_Kong',
    'MO': 'Asia/Macau',
  },
  'Cuba Standard Time': {'001': 'America/Havana'},
  'E. Africa Standard Time': {
    '001': 'Africa/Nairobi',
    'AQ': 'Antarctica/Syowa',
    'DJ': 'Africa/Djibouti',
    'ER': 'Africa/Asmara',
    'ET': 'Africa/Addis_Ababa',
    'KM': 'Indian/Comoro',
    'MG': 'Indian/Antananarivo',
    'SO': 'Africa/Mogadishu',
    'TZ': 'Africa/Dar_es_Salaam',
    'UG': 'Africa/Kampala',
    'YT': 'Indian/Mayotte',
  },
  'E. Australia Standard Time': {'001': 'Australia/Brisbane'},
  'E. Europe Standard Time': {'001': 'Europe/Chisinau'},
  'E. South America Standard Time': {'001': 'America/Sao_Paulo'},
  'Easter Island Standard Time': {'001': 'Pacific/Easter'},
  'Eastern Standard Time': {
    '001': 'America/New_York',
    'BS': 'America/Nassau',
    'CA': 'America/Toronto',
  },
  'Eastern Standard Time (Mexico)': {'001': 'America/Cancun'},
  'Egypt Standard Time': {'001': 'Africa/Cairo'},
  'Ekaterinburg Standard Time': {'001': 'Asia/Yekaterinburg'},
  'Fiji Standard Time': {'001': 'Pacific/Fiji'},
  'FLE Standard Time': {
    '001': 'Europe/Kyiv',
    'AX': 'Europe/Mariehamn',
    'BG': 'Europe/Sofia',
    'EE': 'Europe/Tallinn',
    'FI': 'Europe/Helsinki',
    'LT': 'Europe/Vilnius',
    'LV': 'Europe/Riga',
  },
  'Georgian Standard Time': {'001': 'Asia/Tbilisi'},
  'GMT Standard Time': {
    '001': 'Europe/London',
    'ES': 'Atlantic/Canary',
    'FO': 'Atlantic/Faroe',
    'GG': 'Europe/Guernsey',
    'IE': 'Europe/Dublin',
    'IM': 'Europe/Isle_of_Man',
    'JE': 'Europe/Jersey',
    'PT': 'Europe/Lisbon',
  },
  'Greenland Standard Time': {'001': 'America/Nuuk'},
  'Greenwich Standard Time': {
    '001': 'Atlantic/Reykjavik',
    'BF': 'Africa/Ouagadougou',
    'CI': 'Africa/Abidjan',
    'GH': 'Africa/Accra',
    'GL': 'America/Danmarkshavn',
    'GM': 'Africa/Banjul',
    'GN': 'Africa/Conakry',
    'GW': 'Africa/Bissau',
    'LR': 'Africa/Monrovia',
    'ML': 'Africa/Bamako',
    'MR': 'Africa/Nouakchott',
    'SH': 'Atlantic/St_Helena',
    'SL': 'Africa/Freetown',
    'SN': 'Africa/Dakar',
    'TG': 'Africa/Lome',
  },
  'GTB Standard Time': {
    '001': 'Europe/Bucharest',
    'CY': 'Asia/Nicosia',
    'GR': 'Europe/Athens',
  },
  'Haiti Standard Time': {'001': 'America/Port-au-Prince'},
  'Hawaiian Standard Time': {
    '001': 'Pacific/Honolulu',
    'CK': 'Pacific/Rarotonga',
    'PF': 'Pacific/Tahiti',
  },
  'India Standard Time': {'001': 'Asia/Kolkata'},
  'Iran Standard Time': {'001': 'Asia/Tehran'},
  'Israel Standard Time': {'001': 'Asia/Jerusalem'},
  'Jordan Standard Time': {'001': 'Asia/Amman'},
  'Kaliningrad Standard Time': {'001': 'Europe/Kaliningrad'},
  'Korea Standard Time': {'001': 'Asia/Seoul'},
  'Libya Standard Time': {'001': 'Africa/Tripoli'},
  'Line Islands Standard Time': {'001': 'Pacific/Kiritimati'},
  'Lord Howe Standard Time': {'001': 'Australia/Lord_Howe'},
  'Magadan Standard Time': {'001': 'Asia/Magadan'},
  'Magallanes Standard Time': {'001': 'America/Punta_Arenas'},
  'Marquesas Standard Time': {'001': 'Pacific/Marquesas'},
  'Manitoba Standard Time': {'001': 'America/Winnipeg'},
  'Mauritius Standard Time': {
    '001': 'Indian/Mauritius',
    'RE': 'Indian/Reunion',
    'SC': 'Indian/Mahe',
  },
  'Middle East Standard Time': {'001': 'Asia/Beirut'},
  'Montevideo Standard Time': {'001': 'America/Montevideo'},
  'Morocco Standard Time': {
    '001': 'Africa/Casablanca',
    'EH': 'Africa/El_Aaiun',
  },
  'Mountain Standard Time': {
    '001': 'America/Denver',
    'CA': 'America/Cambridge_Bay',
    'MX': 'America/Ciudad_Juarez',
  },
  'Mountain Standard Time (Mexico)': {'001': 'America/Mazatlan'},
  'Myanmar Standard Time': {'001': 'Asia/Yangon', 'CC': 'Indian/Cocos'},
  'N. Central Asia Standard Time': {'001': 'Asia/Novosibirsk'},
  'Namibia Standard Time': {'001': 'Africa/Windhoek'},
  'Nepal Standard Time': {'001': 'Asia/Kathmandu'},
  'New Zealand Standard Time': {
    '001': 'Pacific/Auckland',
    'AQ': 'Antarctica/McMurdo',
  },
  'Newfoundland Standard Time': {'001': 'America/St_Johns'},
  'Norfolk Standard Time': {'001': 'Pacific/Norfolk'},
  'North Asia East Standard Time': {'001': 'Asia/Irkutsk'},
  'North Asia Standard Time': {'001': 'Asia/Krasnoyarsk'},
  'North Korea Standard Time': {'001': 'Asia/Pyongyang'},
  'Omsk Standard Time': {'001': 'Asia/Omsk'},
  'Pacific SA Standard Time': {'001': 'America/Santiago'},
  'Pacific Standard Time': {'001': 'America/Los_Angeles'},
  'Pacific Standard Time (Mexico)': {'001': 'America/Tijuana'},
  'Pakistan Standard Time': {'001': 'Asia/Karachi'},
  'Paraguay Standard Time': {'001': 'America/Asuncion'},
  'Qyzylorda Standard Time': {'001': 'Asia/Qyzylorda'},
  'Romance Standard Time': {
    '001': 'Europe/Paris',
    'BE': 'Europe/Brussels',
    'DK': 'Europe/Copenhagen',
    'ES': 'Europe/Madrid',
  },
  'Russia Time Zone 3': {'001': 'Europe/Samara'},
  'Russia Time Zone 10': {'001': 'Asia/Srednekolymsk'},
  'Russia Time Zone 11': {'001': 'Asia/Kamchatka'},
  'Russian Standard Time': {'001': 'Europe/Moscow', 'UA': 'Europe/Simferopol'},
  'SA Eastern Standard Time': {
    '001': 'America/Cayenne',
    'AQ': 'Antarctica/Rothera',
    'BR': 'America/Fortaleza',
    'FK': 'Atlantic/Stanley',
    'SR': 'America/Paramaribo',
  },
  'SA Pacific Standard Time': {
    '001': 'America/Bogota',
    'BR': 'America/Rio_Branco',
    'CA': 'America/Atikokan',
    'EC': 'America/Guayaquil',
    'JM': 'America/Jamaica',
    'KY': 'America/Cayman',
    'PA': 'America/Panama',
    'PE': 'America/Lima',
  },
  'SA Western Standard Time': {
    '001': 'America/La_Paz',
    'AG': 'America/Antigua',
    'AI': 'America/Anguilla',
    'AW': 'America/Aruba',
    'BB': 'America/Barbados',
    'BL': 'America/St_Barthelemy',
    'BQ': 'America/Kralendijk',
    'BR': 'America/Manaus',
    'CA': 'America/Blanc-Sablon',
    'CW': 'America/Curacao',
    'DM': 'America/Dominica',
    'DO': 'America/Santo_Domingo',
    'GD': 'America/Grenada',
    'GP': 'America/Guadeloupe',
    'GY': 'America/Guyana',
    'KN': 'America/St_Kitts',
    'LC': 'America/St_Lucia',
    'MF': 'America/Marigot',
    'MQ': 'America/Martinique',
    'MS': 'America/Montserrat',
    'PR': 'America/Puerto_Rico',
    'SX': 'America/Lower_Princes',
    'TT': 'America/Port_of_Spain',
    'VC': 'America/St_Vincent',
    'VG': 'America/Tortola',
    'VI': 'America/St_Thomas',
  },
  'Saint Pierre Standard Time': {'001': 'America/Miquelon'},
  'Sakhalin Standard Time': {'001': 'Asia/Sakhalin'},
  'Samoa Standard Time': {'001': 'Pacific/Apia'},
  'Sao Tome Standard Time': {'001': 'Africa/Sao_Tome'},
  'Saratov Standard Time': {'001': 'Europe/Saratov'},
  'SE Asia Standard Time': {
    '001': 'Asia/Bangkok',
    'AQ': 'Antarctica/Davis',
    'CX': 'Indian/Christmas',
    'ID': 'Asia/Jakarta',
    'KH': 'Asia/Phnom_Penh',
    'LA': 'Asia/Vientiane',
    'VN': 'Asia/Ho_Chi_Minh',
  },
  'Singapore Standard Time': {
    '001': 'Asia/Singapore',
    'BN': 'Asia/Brunei',
    'ID': 'Asia/Makassar',
    'MY': 'Asia/Kuala_Lumpur',
    'PH': 'Asia/Manila',
  },
  'South Africa Standard Time': {
    '001': 'Africa/Johannesburg',
    'BI': 'Africa/Bujumbura',
    'BW': 'Africa/Gaborone',
    'CD': 'Africa/Lubumbashi',
    'LS': 'Africa/Maseru',
    'MW': 'Africa/Blantyre',
    'MZ': 'Africa/Maputo',
    'RW': 'Africa/Kigali',
    'SZ': 'Africa/Mbabane',
    'ZM': 'Africa/Lusaka',
    'ZW': 'Africa/Harare',
  },
  'South Sudan Standard Time': {'001': 'Africa/Juba'},
  'Sri Lanka Standard Time': {'001': 'Asia/Colombo'},
  'Sudan Standard Time': {'001': 'Africa/Khartoum'},
  'Syria Standard Time': {'001': 'Asia/Damascus'},
  'Taipei Standard Time': {'001': 'Asia/Taipei'},
  'Tasmania Standard Time': {'001': 'Australia/Hobart'},
  'Tocantins Standard Time': {'001': 'America/Araguaina'},
  'Tokyo Standard Time': {
    '001': 'Asia/Tokyo',
    'ID': 'Asia/Jayapura',
    'PW': 'Pacific/Palau',
    'TL': 'Asia/Dili',
  },
  'Tomsk Standard Time': {'001': 'Asia/Tomsk'},
  'Tonga Standard Time': {'001': 'Pacific/Tongatapu'},
  'Transbaikal Standard Time': {'001': 'Asia/Chita'},
  'Turkey Standard Time': {'001': 'Europe/Istanbul'},
  'Turks And Caicos Standard Time': {'001': 'America/Grand_Turk'},
  'Ulaanbaatar Standard Time': {'001': 'Asia/Ulaanbaatar'},
  'US Eastern Standard Time': {'001': 'America/Indiana/Indianapolis'},
  'US Mountain Standard Time': {
    '001': 'America/Phoenix',
    'CA': 'America/Creston',
    'MX': 'America/Hermosillo',
  },
  'UTC': {'001': 'Etc/UTC'},
  'UTC+12': {
    'KI': 'Pacific/Tarawa',
    'MH': 'Pacific/Majuro',
    'NR': 'Pacific/Nauru',
    'TV': 'Pacific/Funafuti',
    'UM': 'Pacific/Wake',
    'WF': 'Pacific/Wallis',
  },
  'UTC+13': {'KI': 'Pacific/Kanton', 'TK': 'Pacific/Fakaofo'},
  'UTC-02': {'BR': 'America/Noronha', 'GS': 'Atlantic/South_Georgia'},
  'UTC-08': {'PN': 'Pacific/Pitcairn'},
  'UTC-09': {'PF': 'Pacific/Gambier'},
  'UTC-11': {
    'AS': 'Pacific/Pago_Pago',
    'NU': 'Pacific/Niue',
    'UM': 'Pacific/Midway',
  },
  'Venezuela Standard Time': {'001': 'America/Caracas'},
  'Vladivostok Standard Time': {'001': 'Asia/Vladivostok'},
  'Volgograd Standard Time': {'001': 'Europe/Volgograd'},
  'W. Australia Standard Time': {'001': 'Australia/Perth'},
  'W. Central Africa Standard Time': {
    '001': 'Africa/Lagos',
    'AO': 'Africa/Luanda',
    'BJ': 'Africa/Porto-Novo',
    'CD': 'Africa/Kinshasa',
    'CF': 'Africa/Bangui',
    'CG': 'Africa/Brazzaville',
    'CM': 'Africa/Douala',
    'DZ': 'Africa/Algiers',
    'GA': 'Africa/Libreville',
    'GQ': 'Africa/Malabo',
    'NE': 'Africa/Niamey',
    'TD': 'Africa/Ndjamena',
    'TN': 'Africa/Tunis',
  },
  'W. Europe Standard Time': {
    '001': 'Europe/Berlin',
    'AD': 'Europe/Andorra',
    'AT': 'Europe/Vienna',
    'CH': 'Europe/Zurich',
    'GI': 'Europe/Gibraltar',
    'IT': 'Europe/Rome',
    'LI': 'Europe/Vaduz',
    'LU': 'Europe/Luxembourg',
    'MC': 'Europe/Monaco',
    'MT': 'Europe/Malta',
    'NL': 'Europe/Amsterdam',
    'NO': 'Europe/Oslo',
    'SE': 'Europe/Stockholm',
    'SJ': 'Arctic/Longyearbyen',
    'SM': 'Europe/San_Marino',
    'VA': 'Europe/Vatican',
  },
  'W. Mongolia Standard Time': {'001': 'Asia/Hovd'},
  'West Asia Standard Time': {
    '001': 'Asia/Tashkent',
    'AQ': 'Antarctica/Mawson',
    'KZ': 'Asia/Oral',
    'MV': 'Indian/Maldives',
    'TF': 'Indian/Kerguelen',
    'TJ': 'Asia/Dushanbe',
    'TM': 'Asia/Ashgabat',
  },
  'West Bank Standard Time': {'001': 'Asia/Hebron'},
  'West Pacific Standard Time': {
    '001': 'Pacific/Port_Moresby',
    'AQ': 'Antarctica/DumontDUrville',
    'FM': 'Pacific/Chuuk',
    'GU': 'Pacific/Guam',
    'MP': 'Pacific/Saipan',
  },
  'Yakutsk Standard Time': {'001': 'Asia/Yakutsk'},
  'Yukon Standard Time': {'001': 'America/Whitehorse'},
};

/// The tzdata zone Windows means by [id] in [territory], a country code;
/// null for an ID the table does not know.
String? tzdataZoneFor(String id, {String? territory}) {
  final zones = windowsZones[id];
  return zones?[territory] ?? zones?['001'];
}
