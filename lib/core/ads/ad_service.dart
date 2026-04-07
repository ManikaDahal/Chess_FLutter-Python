import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  RewardedAd? _rewardedAd;
  bool _isAdLoading = false;

  // Ad Unit IDs from .env
  final String _androidRewardedUnitId = dotenv.get('ADMOB_ANDROID_REWARDED_UNIT_ID', fallback: '');
  final String _iosRewardedUnitId = dotenv.get('ADMOB_IOS_REWARDED_UNIT_ID', fallback: '');

  String get rewardedAdUnitId {
    if (Platform.isAndroid) {
      return _androidRewardedUnitId;
    } else if (Platform.isIOS) {
      return _iosRewardedUnitId;
    }
    return '';
  }

  Future<void> initialize() async {
    if (kIsWeb) return;
    await MobileAds.instance.initialize();
    loadRewardedAd();
  }

  void loadRewardedAd() {
    if (kIsWeb || _isAdLoading || _rewardedAd != null) return;

    _isAdLoading = true;
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('RewardedAd loaded: ${ad.adUnitId}');
          _rewardedAd = ad;
          _isAdLoading = false;
          _setAdCallbacks(ad);
        },
        onAdFailedToLoad: (error) {
          debugPrint('RewardedAd failed to load: $error');
          _rewardedAd = null;
          _isAdLoading = false;
        },
      ),
    );
  }

  void _setAdCallbacks(RewardedAd ad) {
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('Ad dismissed.');
        ad.dispose();
        _rewardedAd = null;
        loadRewardedAd(); // Load the next one
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('Ad failed to show: $error');
        ad.dispose();
        _rewardedAd = null;
        loadRewardedAd();
      },
    );
  }

  void showRewardedAd({required Function(RewardItem reward) onUserEarnedReward}) {
    if (_rewardedAd != null) {
      _rewardedAd!.show(
        onUserEarnedReward: (ad, reward) {
          debugPrint('User earned reward: ${reward.amount} ${reward.type}');
          onUserEarnedReward(reward);
        },
      );
    } else {
      debugPrint('Rewarded ad not ready yet.');
      loadRewardedAd();
    }
  }
}
