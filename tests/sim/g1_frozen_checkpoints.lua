-- G1 golden checkpoints frozen at c82ff86 (G1 closure; identical at main 6e03a2f).
-- Copied once from tests/fixtures/replays/ before any G2 change. G2 may change only
-- the tuning_id of those fixtures; tests/sim/replay_spec.lua asserts that every
-- regenerated checkpoint still equals this data (G2 plan §2, §9; clarification 5).
-- Each entry is "<tick>:<hash>". Never regenerate this file.
-- stylua: ignore
return {
  movement_tour = {
    "60:36de2857", "120:b068ae60", "180:db778deb", "240:c02b5b1b",
    "300:ab9b25ab", "360:f59dcea8", "420:ab1a98e3", "480:b2f0eea5",
    "540:3a7674a8", "600:c6f4bbbb", "660:6ebe6df2", "720:b1920ecf",
    "780:2d1c669a", "840:575c4ad5", "900:92e5bfa7", "960:4269ff88",
    "1020:897d85a7", "1080:a5919142", "1140:646d5a19", "1200:704b6aff",
    "1260:1747fc15", "1320:b19b6f93", "1349:30926f75",
  },
  shooting_gallery = {
    "60:360224a2", "120:d44bdfc0", "180:014bd928", "240:d38e216b",
    "300:a9a30ae1", "360:6a499887", "420:07c53755", "480:637ab829",
    "540:bd8d48cb", "600:46b12d14", "660:56c4bbc4", "720:8c229da9",
    "780:00fcb1a9", "840:d4708cbf", "900:7e083e90", "935:2466e75c",
  },
  cancellation_duel = {
    "60:2a032c7f", "120:cd329645", "180:99754103", "240:2e69f29c",
    "300:4d79398b", "360:34d546a8", "420:74fc6e68", "480:d013216c",
    "540:2ef2d77a", "600:c785545c", "660:b74c9fbd", "720:1256221c",
    "780:ed65db74", "840:4fb2c1dc", "900:cae91450", "960:feaa13ce",
    "1020:37891638", "1080:5890b5c2", "1140:4be0b3da", "1200:995ad2fe",
    "1260:22a0bce7", "1284:502fbbb8",
  },
  stress_run = {
    "60:18aec4fa", "120:4b2e8cc9", "180:d9fd1780", "240:13aef0f0",
    "300:fa032a86", "360:e5d8be24", "420:62e64fe6", "480:0d86fc6a",
    "540:0d9ebf73", "600:1088dd7a", "660:2f4782e0", "720:9003e3df",
    "780:4c384313", "840:260d7c22", "900:ac9b6254", "960:e28183b2",
    "1020:a8ae6f1a", "1080:07f3c4db", "1140:9859d5fa", "1200:468e5763",
    "1260:270bc82e", "1320:eef7160f", "1380:802aca09", "1440:52147eca",
    "1500:f06d1c94", "1560:547cb5f4", "1620:42e77863", "1680:de863c85",
    "1740:81c6283b", "1800:51e94309", "1860:6c20bfc7", "1920:7fc3b6fe",
    "1980:6a0304ea", "2040:b2a244c8", "2100:04e86cac", "2160:2e6b573f",
    "2220:6e457fcf", "2280:d3d231fe", "2340:7562b651", "2400:d8cce85a",
    "2460:bd283a3b", "2520:b56796a9", "2580:9e99bde1", "2640:1a2ffdb3",
    "2700:311a2708", "2760:0754f15a", "2820:8f68b0bc", "2880:5f30c85e",
    "2940:4f039933", "3000:5367f3e2", "3060:a9525b65", "3120:3e28d099",
    "3180:52ce1598", "3240:a0fdfab9", "3300:6b2c5fcc", "3360:74ebf82d",
    "3420:24fe8a58", "3480:4f5b0138", "3540:63b8c8eb", "3600:21210800",
  },
}
