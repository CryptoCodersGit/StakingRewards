
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
    نام قرارداد: NativeStakingRewards 

 * @title Native Staking Rewards system 
 * @author Crypto Coders
 * @notice سیستم استیکینگ پاداش دهی غیرمتمرکز بر پایه کوین های شبکه

    توجه:
    این قرارداد آموزشی است و پیش از استفاده واقعی باید
    به‌صورت مستقل بررسی امنیتی و تست شود.
*/
contract NativeStakingRewards {

    // ==========================================
    // 1. متغیرهای اصلی قرارداد
    // ==========================================

    // آدرس سازنده قرارداد که مدیر اصلی محسوب می‌شود.
    address public owner;

    // مشخص می‌کند قرارداد در حالت توقف اضطراری است یا خیر.
    // اگر true باشد، کاربران نمی‌توانند استیک جدید انجام دهند.
    bool public paused;

    // متغیر داخلی برای جلوگیری از حمله Reentrancy.
    // وقتی true باشد، ورود مجدد به توابع محافظت‌شده ممنوع است.
    bool private locked;

    // مجموع ETH استیک‌شده توسط تمام کاربران.
    // این مقدار سرمایه کاربران است، نه بودجه پاداش.
    uint256 public totalStaked;

    // نرخ توزیع پاداش در هر ثانیه، بر حسب Wei.
    uint256 public rewardRate;

    // مدت زمان هر دوره توزیع پاداش، بر حسب ثانیه.
    uint256 public rewardsDuration;

    // زمان پایان دوره فعلی پاداش.
    uint256 public periodFinish;

    // آخرین زمانی که محاسبات پاداش به‌روزرسانی شده‌اند.
    uint256 public lastUpdateTime;

    // مجموع پاداش انباشته‌شده به ازای هر واحد ETH استیک‌شده.
    // برای حفظ دقت، محاسبات در ضریب 10 به توان 18 انجام می‌شوند.
    uint256 public rewardPerTokenStored;

    // مجموع ETHهایی که مدیر تاکنون برای پاداش وارد قرارداد کرده است.
    uint256 public totalRewardsFunded;

    // مجموع پاداش‌هایی که تاکنون به کاربران پرداخت شده است.
    uint256 public totalRewardsPaid;

    // مجموع پاداش‌هایی که در زمان وجود استیک‌کننده
    // طبق نرخ قرارداد انباشته شده‌اند.
    uint256 public totalRewardsAccrued;

    // ضریب دقت محاسبات پاداش.
    // چون Solidity از اعداد اعشاری پشتیبانی نمی‌کند،
    // از این عدد برای انجام محاسبات دقیق‌تر استفاده می‌کنیم.
    uint256 private constant PRECISION = 1e18;


    // ==========================================
    // 2. اطلاعات اختصاصی هر کاربر
    // ==========================================

    // مقدار ETH استیک‌شده هر کاربر را نگهداری می‌کند.
    mapping(address => uint256) public balances;

    // پاداش ذخیره‌شده و دریافت‌نشده هر کاربر.
    mapping(address => uint256) public rewards;

    // آخرین مقدار rewardPerToken که برای هر کاربر محاسبه شده است.
    // از این متغیر برای جلوگیری از محاسبه دوباره پاداش قبلی استفاده می‌کنیم.
    mapping(address => uint256)
        public userRewardPerTokenPaid;


    // ==========================================
    // 3. رویدادهای قرارداد
    // ==========================================

    // وقتی کاربری ETH استیک می‌کند، این رویداد ثبت می‌شود.
    event Staked(address indexed user, uint256 amount);

    // وقتی کاربری سرمایه خود را برداشت می‌کند.
    event Withdrawn(address indexed user, uint256 amount);

    // وقتی پاداش به کاربر پرداخت می‌شود.
    event RewardPaid(address indexed user, uint256 amount);

    // وقتی مدیر بودجه پاداش را تأمین می‌کند.
    event RewardAdded(uint256 amount, uint256 rewardRate);

    // وقتی قرارداد متوقف می‌شود.
    event Paused();

    // وقتی قرارداد از حالت توقف خارج می‌شود.
    event Unpaused();


    // ==========================================
    // 4. سازنده قرارداد
    // ==========================================

    // هنگام Deploy قرارداد فقط یک بار اجرا می‌شود.
    // مدیر و مدت زمان هر دوره پاداش را مشخص می‌کند.
    constructor(uint256 _rewardsDuration) {

        // مدت زمان دوره نباید صفر باشد.
        require(_rewardsDuration > 0, "Invalid duration");

        // شخصی که قرارداد را Deploy کرده، مدیر می‌شود.
        owner = msg.sender;

        // مدت زمان دوره پاداش ذخیره می‌شود.
        rewardsDuration = _rewardsDuration;

    }


    // ==========================================
    // 5. Modifier های کنترلی
    // ==========================================

    // این Modifier اجازه اجرای تابع را فقط به مدیر می‌دهد.
    modifier onlyOwner() {

        // آدرس اجراکننده باید با آدرس مدیر برابر باشد.
        require(msg.sender == owner, "Not owner");

        // پس از عبور از شرط، بدنه تابع اجرا می‌شود.
        _;

    }


    // این Modifier اجازه اجرای تابع را فقط زمانی می‌دهد
    // که قرارداد در حالت توقف نباشد.
    modifier whenNotPaused() {

        require(!paused, "Contract is paused");

        _;

    }


    // این Modifier برای جلوگیری از حمله Reentrancy است.
    modifier nonReentrant() {

        // اگر تابع دیگری در حال اجرا باشد، ورود مجدد ممنوع است.
        require(!locked, "Reentrant call");

        // قرارداد را در حالت قفل قرار می‌دهیم.
        locked = true;

        // بدنه تابع اصلی اجرا می‌شود.
        _;

        // بعد از اجرای موفق تابع، قفل آزاد می‌شود.
        locked = false;

    }


    // ==========================================
    // 6. تابع استیک کردن ETH
    // ==========================================

    // payable یعنی کاربر می‌تواند همراه اجرای تابع ETH ارسال کند.
    function stake()
        external
        payable
        whenNotPaused
        nonReentrant
    {

        // کاربر باید مقداری بیشتر از صفر ETH ارسال کند.
        require(msg.value > 0, "Zero amount");

        // قبل از تغییر موجودی کاربر، پاداش قبلی او محاسبه می‌شود.
        _updateReward(msg.sender);

        // مقدار ETH ارسال‌شده به موجودی استیک کاربر اضافه می‌شود.
        balances[msg.sender] += msg.value;

        // مجموع سرمایه استیک‌شده قرارداد افزایش پیدا می‌کند.
        totalStaked += msg.value;

        // رویداد استیک شدن برای ثبت در بلاکچین منتشر می‌شود.
        emit Staked(msg.sender, msg.value);

    }


    // ==========================================
    // 7. تابع برداشت سرمایه
    // ==========================================

    // کاربر می‌تواند مقدار مشخصی از سرمایه خود را برداشت کند.
    function withdraw(uint256 amount)
        external
        nonReentrant
    {

        // مقدار برداشت نباید صفر باشد.
        require(amount > 0, "Zero amount");

        // ابتدا پاداش کاربر تا همین لحظه محاسبه می‌شود.
        _updateReward(msg.sender);

        // بررسی می‌کنیم کاربر به اندازه درخواست خود سرمایه داشته باشد.
        require(
            balances[msg.sender] >= amount,
            "Insufficient balance"
        );

        // مقدار برداشت‌شده از موجودی کاربر کم می‌شود.
        balances[msg.sender] -= amount;

        // مجموع ETH استیک‌شده قرارداد کاهش پیدا می‌کند.
        totalStaked -= amount;

        // ETH به آدرس کاربر ارسال می‌شود.
        _sendETH(msg.sender, amount);

        // رویداد برداشت سرمایه ثبت می‌شود.
        emit Withdrawn(msg.sender, amount);

    }


    // ==========================================
    // 8. تابع دریافت پاداش
    // ==========================================

    // کاربر با اجرای این تابع پاداش خود را دریافت می‌کند.
    function claimReward()
        external
        nonReentrant
    {

        // ابتدا پاداش کاربر تا لحظه اجرای تراکنش به‌روز می‌شود.
        _updateReward(msg.sender);

        // مقدار پاداش قابل دریافت کاربر خوانده می‌شود.
        uint256 reward = rewards[msg.sender];

        // اگر پاداشی وجود نداشته باشد، تراکنش متوقف می‌شود.
        require(reward > 0, "No rewards");

        // بررسی می‌کنیم پاداش در محدوده پاداش انباشته‌شده
        // و پرداخت‌نشده قرارداد باشد.
        require(
            reward <= totalRewardsAccrued - totalRewardsPaid,
            "Insufficient reward accounting"
        );

        // قبل از انتقال ETH، پاداش کاربر صفر می‌شود.
        // این کار از دریافت دوباره همان پاداش جلوگیری می‌کند.
        rewards[msg.sender] = 0;

        // مجموع پاداش‌های پرداخت‌شده افزایش پیدا می‌کند.
        totalRewardsPaid += reward;

        // پاداش ETH به کیف پول کاربر ارسال می‌شود.
        _sendETH(msg.sender, reward);

        // رویداد پرداخت پاداش ثبت می‌شود.
        emit RewardPaid(msg.sender, reward);

    }


    // ==========================================
    // 9. تابع خروج کامل کاربر
    // ==========================================

    // این تابع تمام سرمایه و پاداش کاربر را پرداخت می‌کند.
    function exit()
        external
        nonReentrant
    {

        // ابتدا پاداش کاربر محاسبه و به‌روزرسانی می‌شود.
        _updateReward(msg.sender);

        // کل سرمایه استیک‌شده کاربر خوانده می‌شود.
        uint256 stakedAmount = balances[msg.sender];

        // کل پاداش دریافت‌نشده کاربر خوانده می‌شود.
        uint256 reward = rewards[msg.sender];

        // اگر نه سرمایه‌ای وجود داشته باشد و نه پاداشی،
        // اجرای تابع ضرورتی ندارد.
        require(
            stakedAmount > 0 || reward > 0,
            "Nothing to withdraw"
        );

        // موجودی استیک کاربر صفر می‌شود.
        balances[msg.sender] = 0;

        // مجموع سرمایه استیک‌شده کاهش پیدا می‌کند.
        totalStaked -= stakedAmount;

        // پاداش ذخیره‌شده کاربر صفر می‌شود.
        rewards[msg.sender] = 0;

        // اگر کاربر پاداش داشته باشد، حسابداری پرداخت به‌روز می‌شود.
        if (reward > 0) {

            // از پرداخت بیشتر از پاداش انباشته‌شده جلوگیری می‌کنیم.
            require(
                reward <= totalRewardsAccrued - totalRewardsPaid,
                "Insufficient reward accounting"
            );

            // مجموع پاداش‌های پرداخت‌شده افزایش پیدا می‌کند.
            totalRewardsPaid += reward;

        }

        // سرمایه و پاداش با هم جمع می‌شوند.
        uint256 totalAmount = stakedAmount + reward;

        // اگر مبلغی برای پرداخت وجود داشته باشد، ارسال انجام می‌شود.
        if (totalAmount > 0) {

            _sendETH(msg.sender, totalAmount);

        }

        // رویداد برداشت سرمایه منتشر می‌شود.
        emit Withdrawn(msg.sender, stakedAmount);

        // اگر پاداشی پرداخت شده باشد، رویداد آن نیز ثبت می‌شود.
        if (reward > 0) {

            emit RewardPaid(msg.sender, reward);

        }

    }


    // ==========================================
    // 10. تأمین بودجه پاداش توسط مدیر
    // ==========================================

    // فقط مدیر می‌تواند ETH را برای پاداش وارد استخر کند.
    // این ETH با سرمایه کاربران که از stake دریافت شده متفاوت است.
    function notifyRewardAmount()
        external
        payable
        onlyOwner
        whenNotPaused
    {

        // مدیر باید مقداری بیشتر از صفر ETH ارسال کند.
        require(msg.value > 0, "Zero reward");

        // ابتدا حسابداری پاداش دوره قبلی به‌روزرسانی می‌شود.
        _updateReward(address(0));

        // متغیری برای نگهداری پاداش باقی‌مانده دوره قبلی.
        uint256 leftover = 0;

        // اگر دوره قبلی هنوز تمام نشده باشد،
        // پاداش برنامه‌ریزی‌شده باقی‌مانده را محاسبه می‌کنیم.
        if (block.timestamp < periodFinish) {

            leftover =
                (periodFinish - block.timestamp)
                * rewardRate;

        }

        // پاداش جدید مدیر با پاداش باقی‌مانده جمع می‌شود.
        uint256 newReward =
            msg.value + leftover;

        // نرخ جدید پاداش در هر ثانیه محاسبه می‌شود.
        uint256 newRate =
            newReward / rewardsDuration;

        // اگر نرخ پاداش صفر شود، تأمین بودجه پذیرفته نمی‌شود.
        require(newRate > 0, "Reward rate too low");

        // مقدار ETH جدید به مجموع بودجه تأمین‌شده اضافه می‌شود.
        totalRewardsFunded += msg.value;

        // نرخ جدید پاداش ذخیره می‌شود.
        rewardRate = newRate;

        // زمان شروع محاسبه دوره جدید ثبت می‌شود.
        lastUpdateTime = block.timestamp;

        // زمان پایان دوره جدید تعیین می‌شود.
        periodFinish =
            block.timestamp + rewardsDuration;

        // مجموع پاداش‌های انباشته‌شده ولی پرداخت‌نشده محاسبه می‌شود.
        uint256 unpaidRewards =
            totalRewardsAccrued - totalRewardsPaid;

        // مجموع پاداشی که قرار است در دوره جدید توزیع شود.
        uint256 futureRewards =
            rewardRate * rewardsDuration;

        // بررسی می‌کنیم بودجه موجود برای پوشش تعهدات کافی باشد.
        require(
            unpaidRewards + futureRewards
                <= totalRewardsFunded - totalRewardsPaid,
            "Insufficient reward funds"
        );

        // رویداد تأمین پاداش منتشر می‌شود.
        emit RewardAdded(msg.value, rewardRate);

    }


    // ==========================================
    // 11. محاسبات پاداش
    // ==========================================

    // آخرین زمانی را برمی‌گرداند که پاداش در دوره فعلی محاسبه می‌شود.
    function lastTimeRewardApplicable()
        public
        view
        returns (uint256)
    {

        // اگر هنوز دوره تمام نشده باشد، زمان فعلی برگردانده می‌شود.
        if (block.timestamp < periodFinish) {

            return block.timestamp;

        }

        // اگر دوره تمام شده باشد، زمان پایان دوره برگردانده می‌شود.
        return periodFinish;

    }


    // مقدار پاداش انباشته‌شده به ازای هر ETH استیک‌شده را محاسبه می‌کند.
    function rewardPerToken()
        public
        view
        returns (uint256)
    {

        // اگر هیچ سرمایه‌ای استیک نشده باشد،
        // پاداش جدیدی به کاربران تعلق نمی‌گیرد.
        if (totalStaked == 0) {

            return rewardPerTokenStored;

        }

        // مدت زمان سپری‌شده از آخرین به‌روزرسانی محاسبه می‌شود.
        uint256 elapsed =
            lastTimeRewardApplicable() - lastUpdateTime;

        // پاداش جدید به ازای هر واحد ETH محاسبه می‌شود
        // و به مقدار ذخیره‌شده قبلی اضافه می‌گردد.
        return
            rewardPerTokenStored +
            (
                elapsed * rewardRate * PRECISION
            ) / totalStaked;

    }


    // پاداش قابل دریافت یک آدرس را محاسبه می‌کند.
    function earned(address account)
        public
        view
        returns (uint256)
    {

        // پاداش جدید کاربر بر اساس موجودی استیک او محاسبه می‌شود.
        uint256 newReward =
            (
                balances[account] *
                (
                    rewardPerToken() -
                    userRewardPerTokenPaid[account]
                )
            ) / PRECISION;

        // پاداش جدید با پاداش ذخیره‌شده قبلی جمع می‌شود.
        return rewards[account] + newReward;

    }


    // ==========================================
    // 12. به‌روزرسانی حسابداری پاداش
    // ==========================================

    // این تابع هم حسابداری کلی و هم حسابداری یک کاربر را به‌روز می‌کند.
    function _updateReward(address account)
        internal
    {

        // آخرین زمان قابل محاسبه پاداش مشخص می‌شود.
        uint256 applicableTime =
            lastTimeRewardApplicable();

        // اگر کاربری سرمایه استیک‌شده داشته باشد،
        // پاداش مربوط به زمان سپری‌شده به حسابداری اضافه می‌شود.
        if (totalStaked > 0) {

            // مدت زمان سپری‌شده از آخرین به‌روزرسانی محاسبه می‌شود.
            uint256 elapsed =
                applicableTime - lastUpdateTime;

            // پاداش انباشته‌شده در این بازه به مجموع اضافه می‌شود.
            totalRewardsAccrued +=
                elapsed * rewardRate;

        }

        // مقدار کلی پاداش به ازای هر ETH به‌روزرسانی می‌شود.
        rewardPerTokenStored = rewardPerToken();

        // زمان آخرین به‌روزرسانی ثبت می‌شود.
        lastUpdateTime = applicableTime;

        // اگر آدرس کاربر صفر نباشد،
        // اطلاعات پاداش همان کاربر نیز به‌روزرسانی می‌شود.
        if (account != address(0)) {

            // پاداش قابل دریافت کاربر محاسبه و ذخیره می‌شود.
            rewards[account] = earned(account);

            // مشخص می‌کنیم کاربر تا کدام مقدار پاداش محاسبه شده است.
            userRewardPerTokenPaid[account] =
                rewardPerTokenStored;

        }

    }


    // ==========================================
    // 13. تابع داخلی انتقال ETH
    // ==========================================

    // برای جلوگیری از تکرار کد انتقال ETH،
    // یک تابع داخلی برای ارسال ETH می‌سازیم.
    function _sendETH(
        address to,
        uint256 amount
    )
        internal
    {

        // ETH به آدرس مقصد ارسال می‌شود.
        // call نسبت به transfer محدودیت ثابت گس 2300 ندارد.
        (bool success, ) =
            payable(to).call{value: amount}("");

        // اگر انتقال ناموفق باشد، کل تراکنش برگردانده می‌شود.
        require(success, "ETH transfer failed");

    }


    // ==========================================
    // 14. توقف و فعال‌سازی مجدد قرارداد
    // ==========================================

    // فقط مدیر می‌تواند قرارداد را متوقف کند.
    function pause()
        external
        onlyOwner
    {

        // وضعیت قرارداد به حالت توقف تغییر می‌کند.
        paused = true;

        // رویداد توقف ثبت می‌شود.
        emit Paused();

    }


    // فقط مدیر می‌تواند قرارداد را از حالت توقف خارج کند.
    function unpause()
        external
        onlyOwner
    {

        // وضعیت قرارداد دوباره فعال می‌شود.
        paused = false;

        // رویداد فعال‌سازی مجدد ثبت می‌شود.
        emit Unpaused();

    }


    // ==========================================
    // 15. توابع مشاهده اطلاعات
    // ==========================================

    // موجودی ETH فعلی قرارداد را برمی‌گرداند.
    function contractBalance()
        external
        view
        returns (uint256)
    {

        return address(this).balance;

    }


    // مقدار بودجه پاداشی را برمی‌گرداند
    // که تاکنون پرداخت نشده است.
    function remainingRewardFunds()
        external
        view
        returns (uint256)
    {

        return totalRewardsFunded - totalRewardsPaid;

    }

}
