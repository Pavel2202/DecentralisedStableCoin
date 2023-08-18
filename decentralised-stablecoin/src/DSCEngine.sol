// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DecentralisedStableCoin} from "./DecentralisedStableCoin.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

contract DSCEngine is ReentrancyGuard {
    error ArrayMissmatch();
    error TransferFailed();
    error AmountMustNotBeZero();
    error TokenNotAllowed();
    error BreaksHealthFactor(uint256 healthFactor);
    error MintFailed();

    DecentralisedStableCoin private immutable dsc;
    uint256 private constant ADDITIONAL_FEE_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address collateralToken => address priceFeed) private priceFeeds;
    mapping(address user => mapping(address collateralToken => uint256 amount)) private collateralDeposited;
    mapping(address user => uint256 amountMinted) private dscMinted;
    address[] private collateralTokens;

    event CollateralDeposited(address indexed user, address indexed tokenCollateral, uint256 amountCollateral);

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert AmountMustNotBeZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (priceFeeds[token] == address(0)) {
            revert TokenNotAllowed();
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address _dsc) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert ArrayMissmatch();
        }

        for (uint256 i; i < tokenAddresses.length; ++i) {
            priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            collateralTokens.push(tokenAddresses[i]);
        }

        dsc = DecentralisedStableCoin(_dsc);
    }

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert TransferFailed();
        }
    }

    function mintDsc(uint256 amount) external moreThanZero(amount) nonReentrant {
        dscMinted[msg.sender] += amount;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool success = dsc.mint(msg.sender, amount);
        if (!success) {
            revert MintFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = dscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert BreaksHealthFactor(userHealthFactor);
        }
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i; i < collateralTokens.length; ++i) {
            address token = collateralTokens[i];
            uint256 amount = collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEE_PRECISION) * amount) / PRECISION;
    }
}
