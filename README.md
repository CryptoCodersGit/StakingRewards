# Crypto Coders | Solidity Native ETH Staking Rewards

قرارداد هوشمند استیکینگ و توزیع پاداش بر پایه Native ETH به زبان Solidity با الگوریتم محاسبه پاداش تجمعی بر اساس زمان.

## ساختار فایل‌ها و قرارداد

| فایل | نام قرارداد | نسخه کامپایلر | توضیحات |
|---|---|---|---|
| `NativeStakingRewards .sol` | `NativeStakingRewards` | `^0.8.24` | سیستم استیکینگ ETH، محاسبه لحظه‌ای پاداش با دقت بالا و مدیریت دوره‌های پاداش‌دهی |

## متغیرهای حالت کلیدی
- `owner`: مالک قرارداد و تأمین‌کننده استخر پاداش
- `totalStaked`: کل مقدار ETH استیک‌شده توسط کاربران
- `rewardRate`: نرخ توزیع پاداش در هر ثانیه
- `rewardsDuration`: طول دوره پاداش‌دهی بر حسب ثانیه
- `periodFinish`: زمان پایان دوره فعلی پاداش‌دهی
- `rewardPerTokenStored`: شاخص تجمعی پاداش به ازای هر واحد توکن استیک‌شده
- `balances`، `rewards` و `userRewardPerTokenPaid`: نگاشت‌های نگهداری موجودی استیک و پاداش هر کاربر

## توابع اصلی
- `constructor(uint256 _rewardsDuration)`: تنظیم مالک و طول دوره پاداش‌دهی
- `stake() payable`: استیک کردن ETH توسط کاربر (`whenNotPaused`, `nonReentrant`)
- `withdraw(uint256 amount)`: برداشت اصل سرمایه استیک‌شده توسط کاربر
- `claimReward()`: دریافت پاداش‌های تعلق‌گرفته به کاربر
- `exit()`: برداشت هم‌زمان کل اصل سرمایه و پاداش‌های کاربر
- `notifyRewardAmount() payable`: تزریق ETH پاداش توسط مالک (`onlyOwner`) و به‌روزرسانی `rewardRate`
- `setRewardsDuration(uint256 _rewardsDuration)`، `pause()` و `unpause()`: مدیریت دوره پاداش و توقف اضطراری توسط مالک
- `rewardPerToken()`، `earned(address account)`، `contractBalance()` و `remainingRewardFunds()`: توابع محاسبه و مشاهده وضعیت
