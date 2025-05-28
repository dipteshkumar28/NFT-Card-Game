// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract NftCardGame is ERC1155Supply, Ownable {
    uint8 public constant MAX_STRENGTH = 10;
    string public baseURI;

    enum BattleStatus {
        PENDING,
        IN_PROGRESS,
        FINISHED
    }

    struct GameToken {
        uint8 id;
        uint8 atk;
        uint8 def;
    }

    struct Player {
        address addr;
        uint8 mana;
        uint8 health;
        bool inBattle;
        GameToken token;
    }

    struct Battle {
        BattleStatus status;
        bytes32 battleHash;
        string name;
        address[2] players;
        uint8[2] moves;
        address winner;
    }

    Player[] internal players;
    GameToken[] public gameTokens; // Array of game tokens

    Battle[] internal battles;

    mapping(address => uint256) internal playerIndex;
    mapping(bytes32 => uint256) internal battleIndex;

    event NewPlayer(address indexed user);
    event NewBattle(bytes32 indexed battleHash, address p1, address p2);
    event BattleMove(bytes32 indexed battleHash, bool isFirstMove);
    event BattleEnded(
        bytes32 indexed battleHash,
        address winner,
        address loser
    );
    event RoundEnded(address[2] damaged);

    constructor(
        address initialOwner,
        string memory _baseURI
    ) ERC1155(_baseURI) Ownable(initialOwner) {
        baseURI = _baseURI;

        // Initialize with dummy at index 0 to avoid 0-based ambiguity
        players.push(Player(address(0), 0, 0, false, GameToken(0, 0, 0)));
        gameTokens.push(GameToken(0, 0, 0));
        battles.push(
            Battle({
                status: BattleStatus.PENDING,
                battleHash: bytes32(0),
                name: "",
                players: [address(0), address(0)],
                moves: [0, 0],
                winner: address(0)
            })
        );
    }

    modifier onlyPlayer() {
        require(playerIndex[msg.sender] != 0, "Not a player");
        _;
    }

    function registerPlayer() external {
        require(playerIndex[msg.sender] == 0, "Already registered");
        uint8 atk = _rand(MAX_STRENGTH, msg.sender);
        uint8 def = MAX_STRENGTH - atk;
        uint8 id = uint8(
            uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender))) %
                6
        );

        players.push(
            Player(msg.sender, 10, 25, false, GameToken(id, atk, def))
        );
        playerIndex[msg.sender] = players.length - 1;
        _mint(msg.sender, id, 1, "");

        emit NewPlayer(msg.sender);
    }

    function createBattle(
        string calldata name
    ) external onlyPlayer returns (bytes32) {
        bytes32 hash = keccak256(abi.encodePacked(name));
        require(battleIndex[hash] == 0, "Exists");

        battles.push(
            Battle(
                BattleStatus.PENDING,
                hash,
                "", // name
                [msg.sender, address(0)],
                [0, 0],
                address(0)
            )
        );
        battleIndex[hash] = battles.length - 1;
        return hash;
    }

    function joinBattle(bytes32 hash) external onlyPlayer {
        uint256 idx = battleIndex[hash];
        Battle storage b = battles[idx];
        require(b.status == BattleStatus.PENDING, "Started");
        require(b.players[0] != msg.sender, "Same player");

        b.players[1] = msg.sender;
        b.status = BattleStatus.IN_PROGRESS;
        players[playerIndex[b.players[0]]].inBattle = true;
        players[playerIndex[b.players[1]]].inBattle = true;

        emit NewBattle(hash, b.players[0], b.players[1]);
    }

    function attackOrDefend(uint8 choice, bytes32 hash) external onlyPlayer {
        require(choice == 1 || choice == 2, "Invalid");
        Battle storage b = battles[battleIndex[hash]];
        require(b.status == BattleStatus.IN_PROGRESS, "Not in progress");

        uint8 idx = (b.players[0] == msg.sender) ? 0 : 1;
        require(b.players[idx] == msg.sender, "Not player");
        require(b.moves[idx] == 0, "Move made");

        if (choice == 1)
            require(players[playerIndex[msg.sender]].mana >= 3, "No mana");
        b.moves[idx] = choice;

        emit BattleMove(hash, b.moves[0] == 0 || b.moves[1] == 0);

        if (b.moves[0] != 0 && b.moves[1] != 0) _resolve(hash);
    }

    function _resolve(bytes32 hash) internal {
        Battle storage b = battles[battleIndex[hash]];
        Player storage p1 = players[playerIndex[b.players[0]]];
        Player storage p2 = players[playerIndex[b.players[1]]];

        address[2] memory damaged;

        if (b.moves[0] == 1 && b.moves[1] == 1) {
            if (p1.token.atk >= p2.health) return _endBattle(b.players[0], b);
            if (p2.token.atk >= p1.health) return _endBattle(b.players[1], b);
            p1.health -= p2.token.atk;
            p2.health -= p1.token.atk;
            p1.mana -= 3;
            p2.mana -= 3;
            damaged = b.players;
        } else if (b.moves[0] == 1 && b.moves[1] == 2) {
            uint8 totalDef = p2.health + p2.token.def;
            if (p1.token.atk >= totalDef) return _endBattle(b.players[0], b);
            p2.health = totalDef - p1.token.atk;
            p1.mana += 3;
            p2.mana -= 3;
            damaged[1] = b.players[1];
        } else if (b.moves[0] == 2 && b.moves[1] == 1) {
            p1.mana -= 3;
            p2.mana += 3;
            damaged[0] = b.players[0];
        }

        emit RoundEnded(damaged);
        b.moves = [0, 0];

        p1.token = _randToken(b.players[0]);
        p2.token = _randToken(b.players[1]);
    }

    function _endBattle(address winner, Battle storage b) internal {
        b.status = BattleStatus.FINISHED;
        b.winner = winner;

        for (uint8 i = 0; i < 2; i++) {
            Player storage p = players[playerIndex[b.players[i]]];
            p.inBattle = false;
            p.health = 25;
            p.mana = 10;
        }

        address loser = (winner == b.players[0]) ? b.players[1] : b.players[0];
        emit BattleEnded(b.battleHash, winner, loser);
    }

    function quitBattle(bytes32 hash) external {
        Battle storage b = battles[battleIndex[hash]];
        require(
            b.players[0] == msg.sender || b.players[1] == msg.sender,
            "Not in"
        );

        address winner = (b.players[0] == msg.sender)
            ? b.players[1]
            : b.players[0];
        _endBattle(winner, b);
    }

    function _rand(uint8 max, address sender) internal view returns (uint8) {
        uint256 r = uint256(
            keccak256(
                abi.encodePacked(block.prevrandao, block.timestamp, sender)
            )
        );
        return uint8((r % max) + 1);
    }

    function _randToken(
        address sender
    ) internal view returns (GameToken memory) {
        uint8 atk = _rand(MAX_STRENGTH, sender);
        return GameToken(0, atk, MAX_STRENGTH - atk);
    }

    function setURI(string calldata newURI) external onlyOwner {
        baseURI = newURI;
        _setURI(newURI);
    }

    function uri(uint256 id) public view override returns (string memory) {
        return string(abi.encodePacked(baseURI, "/", _toStr(id), ".json"));
    }

    function _toStr(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 j = v;
        uint256 l;
        while (j != 0) {
            l++;
            j /= 10;
        }
        bytes memory s = new bytes(l);
        while (v != 0) {
            s[--l] = bytes1(uint8(48 + (v % 10)));
            v /= 10;
        }
        return string(s);
    }
}
