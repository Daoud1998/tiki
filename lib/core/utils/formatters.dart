import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class Formatters {
  static String priceMRU(num value) {
    final f = NumberFormat.decimalPattern();
    return '${f.format(value)} MRU';
  }

  /// Localized "time ago" that respects current locale.
  static String timeAgo(BuildContext context, DateTime dateTime) {
    final locale = Localizations.localeOf(context).languageCode.toLowerCase();
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    final minutes = diff.inMinutes;
    final hours = diff.inHours;
    final days = diff.inDays;

    if (diff.inSeconds < 45) {
      return _t(locale, ar: 'الآن', fr: "à l'instant", en: 'just now');
    }
    if (minutes < 60) {
      return _t(locale,
          ar: 'قبل ${_arNumber(minutes)} دقيقة',
          fr: 'il y a $minutes min',
          en: '$minutes min ago');
    }
    if (hours < 24) {
      return _t(locale,
          ar: 'قبل ${_arNumber(hours)} ساعة',
          fr: 'il y a $hours h',
          en: '$hours h ago');
    }
    if (days < 7) {
      return _t(locale,
          ar: 'قبل ${_arNumber(days)} يوم',
          fr: 'il y a $days j',
          en: '$days d ago');
    }
    final weeks = (days / 7).floor();
    if (weeks < 5) {
      return _t(locale,
          ar: 'قبل ${_arNumber(weeks)} أسبوع',
          fr: 'il y a $weeks sem',
          en: '$weeks w ago');
    }
    final months = (days / 30).floor();
    return _t(locale,
        ar: 'قبل ${_arNumber(months)} شهر',
        fr: 'il y a $months mois',
        en: '$months mo ago');
  }

  static String _t(String locale,
      {required String ar, required String fr, required String en}) {
    if (locale == 'fr') return fr;
    if (locale == 'en') return en;
    return ar;
  }

  static String _arNumber(int n) {
    const map = {
      '0': '٠',
      '1': '١',
      '2': '٢',
      '3': '٣',
      '4': '٤',
      '5': '٥',
      '6': '٦',
      '7': '٧',
      '8': '٨',
      '9': '٩'
    };
    final s = n.toString();
    return s.split('').map((c) => map[c] ?? c).join();
  }
}
