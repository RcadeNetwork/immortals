// SPDX-License-Identifier: MIT

/*
                                                 .
        .-=-:    ..:  .:::::::  ::::::---:     -##++*+*.::----:  -==-   ---.--::---=.
      =#=-=+=+#=@+=+%##=#@=--%+##=@*-=##==#=-*#==*#= :%@*-:**+=#*@-=@%-+@:@@+-:+**=#=
     =%..%@@@--@@+.-@=+@@@@=.:%%-@@*::@@+.+@@::*@@@#=.#@#::@@%..@@=.:*@@@.@@#. %=-+=
     =@-..*@@@@@@*:::.*@@@@@+..-@@@#:.#*-:*@@.-@@@@%=:=@#:.*=:+%@@=+=.:%@:@@#..%*++:
      *@*-..-+@@@+.-@=.-%@@@@.:#@@@*:-@@@=.*@-.+*@@@:.+@#.:@%::#@@=*@#:.*:@@#..=+=%-
     -#*@@%=-:.%@*.-@@#-.:=#%==++@@*..#%#:=%@%-.:--.:#@@*..@@@-.-#+*@@@-..@@%..#+:.
     +*.@@@@#..#@=::@@@@%*+=--=+%@@@@@@@@@@@@@@@%##%@@@@@%%@@@@%=-::--#@*.@@%..*+..:
      %*=+*+:=*@@@@@@@@%#%##****##**+++*###+##*###**+++**#*****#%##@@@@@@@@@@#*+**+%+
       -#@@@@@@@@@@%%%%%%#*++**%%#++++*#%*******#%#*+++*#%%#*++*#%%%#%%@@@@@@@@@@@%#
     :+***+++***@@@%###*****#@@#**#@@@@%**#@@#***#****#@@@@%**+**#%@@###%@@@@%#******%+
   .#*-:::---:::%@@@-:--====:@@@-::=@@@@=:#@@@-:=+++++-@@%-:=+++--=@@#::@@@#=::----::-@
  :@+::=#@@@@@%*+@@@-:*@@@@@@%@@--=--%@@=-+@@@-:#@@@@%@@@+--%@@@@@+@@%::@@%-:=@@@@@%#=%-
  %*::+@@@@%%%%%#%@@=--====-@@@@--##-:#@=-*@@%--:::::=@@@@+-::-=+#@@@#-:@@%--:=+*#%@@@%*
 .@+--*@@@@------%@@=-+**#**@@@@=-%@%=-+=-*@@@=-#%%%%#@@@#@@%##*=--%@#-:@@@@*+=---::-+@-
 .@#---@@@%%@@+--@@@=-*@@@@@%%@%=-%@@@+-==*@@@==+*###**#@*-*#%@@%=-+@#--@@*%@@@@@%#+---@
  +@+--=#@@@@%+=-@@@==------=%@%==*@@@@*+++@@%+*+++++++@@@++=---==*@@#=-@@%-=*#%@%%*=-=@:
   *@#+==----====%@%##%%%%%@@@@@@%%%#*#####**##*#########%##@@@@@@#%@%#*#@@*===---===*@*
    :*@%##**##%@%#=+==--::..                                  ..    :-==+=%@@@%%%%%@%*-
       :-=++=-:                                                            .  .:--:.
*/

pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../../../thirdparty/falkor-contracts/utils/vrf/IVRFSubcriber.sol";
import "../../../thirdparty/falkor-contracts/utils/vrf/IVRFKeeper.sol";

import "../interfaces/IERC721ASafeMintable.sol";

import { ERC721AUpgradeable } from "../../../thirdparty/opensea/seadrop-upgradeable/lib/erc721a-upgradeable/contracts/ERC721AUpgradeable.sol";
import { ERC721ContractMetadataUpgradeable } from "../../../thirdparty/opensea/seadrop-upgradeable/src/ERC721ContractMetadataUpgradeable.sol";
import { COLLECTION_ADMIN_ROLE, MINTER_ROLE } from "../../WLRoleConstants.sol";

contract Immortals is
	Initializable,
	ERC721ContractMetadataUpgradeable,
	AccessControlEnumerableUpgradeable,
	UUPSUpgradeable,
	IERC721ASafeMintable,
	IVRFSubcriber
{
	// ====================================================
	// ERRORS
	// ====================================================
	error Unauthorized();
	error AlreadyRevealed();
	error NotFullyMinted();
	error InvalidToken();
	error MintQuantityExceedsMaxSupply(uint256 total, uint256 maxSupply);

	// ====================================================
	// STATE
	// ====================================================
	IVRFKeeper public vrfKeeperContract;

	/// @notice See {ERC721SeaDropRandomOffset}
	uint256 public constant _FALSE = 1;
	uint256 public constant _TRUE = 2;

	uint256 public revealed;
	uint256 public randomOffset;

	// ====================================================
	// CONSTRUCTOR / INITIALIZER
	// ====================================================
	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	function initialize(string memory name_, string memory symbol_) external initializer initializerERC721A {
		__ERC721ContractMetadata_init(name_, symbol_);

		__AccessControlEnumerable_init();
		__UUPSUpgradeable_init();

		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		_setupRole(MINTER_ROLE, msg.sender);
		_setRoleAdmin(COLLECTION_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
		_setRoleAdmin(MINTER_ROLE, DEFAULT_ADMIN_ROLE);

		revealed = _FALSE;
	}

	// ====================================================
	// OVERRIDES
	// ====================================================
	function _startTokenId() internal view virtual override returns (uint256) {
		return 1;
	}

	function supportsInterface(
		bytes4 interfaceId
	) public view override(AccessControlEnumerableUpgradeable, ERC721ContractMetadataUpgradeable) returns (bool) {
		return
			AccessControlEnumerableUpgradeable.supportsInterface(interfaceId) ||
			ERC721ContractMetadataUpgradeable.supportsInterface(interfaceId) ||
			super.supportsInterface(interfaceId);
	}

	function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(COLLECTION_ADMIN_ROLE) {}

	function _beforeTokenTransfers(
		address _from,
		address _to,
		uint256 _startId,
		uint256 _quantity
	) internal virtual override(ERC721AUpgradeable) {
		super._beforeTokenTransfers(_from, _to, _startId, _quantity);
	}

	// ====================================================
	// INTERNAL
	// ====================================================
	function _vrfCallback(uint256 /*requestId*/, uint256[] memory randomWords) external {
		if (msg.sender != address(vrfKeeperContract)) {
			revert Unauthorized();
		}

		if (revealed == _TRUE) {
			revert AlreadyRevealed();
		}

		randomOffset = (randomWords[0] % (maxSupply() - 1)) + 1;
		revealed = _TRUE;
	}

	// ====================================================
	// ROLE GATED
	// ====================================================
	function setVrfKeeperContract(IVRFKeeper keeperContract) public onlyRole(COLLECTION_ADMIN_ROLE) {
		vrfKeeperContract = keeperContract;
	}

	function setRandomOffset() external onlyRole(COLLECTION_ADMIN_ROLE) {
		if (revealed == _TRUE) {
			revert AlreadyRevealed();
		}

		if (_totalMinted() != maxSupply()) {
			revert NotFullyMinted();
		}

		vrfKeeperContract.requestRandomness(1, this);
	}

	function setRevealedStatus(bool status) public onlyRole(COLLECTION_ADMIN_ROLE) {
		if (status) {
			if (_totalMinted() != maxSupply()) {
				revert NotFullyMinted();
			}

			revealed = _TRUE;
		} else revealed = _FALSE;
	}

	function safeMint(address to, uint256 quantity) public onlyRole(MINTER_ROLE) {
		if (totalSupply() + quantity > maxSupply()) {
			revert MintQuantityExceedsMaxSupply(_totalMinted() + quantity, maxSupply());
		}

		_safeMint(to, quantity);
	}

	// ====================================================
	// PUBLIC API
	// ====================================================
	function tokenURI(uint256 tokenId) public view override returns (string memory) {
		if (!_exists(tokenId)) {
			revert InvalidToken();
		}

		if (revealed == _FALSE) {
			string memory baseURI = _baseURI();

			if (bytes(baseURI)[bytes(baseURI).length - 1] != bytes("/")[0]) {
				return baseURI;
			}
			return super.tokenURI(tokenId);
		}
		uint256 id = ((tokenId + randomOffset) % maxSupply()) + _startTokenId();
		return super.tokenURI(id);
	}

	function startTokenId() public view returns (uint256) {
		return _startTokenId();
	}
}
