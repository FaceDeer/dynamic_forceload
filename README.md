This mod is similar to Rubenwardy's "forceload" mod, but with expanded capabilities intended to make it safe for use by any number of players on a public server.

"Forceloading" a map block causes the game to continue running time in that block as if a player was present there. ABMs continue to run, timers tick, and so forth. This places a burden on the server, however, roughly equivalent to having an extra player online at that location (though without the networking overhead of communicating with a player). As a result, a limit must be placed on the maximum number of blocks that can be forceloaded in this manner.

A player marks a map block for forceloading by placing a forceload anchor node in the world. This registers the location and player who placed it with dynamic_forceload's global queue. At regular intervals the mod will attempt to set a new registered location as forceloaded, advancing one by one through the queued locations, and when the maximum number of forceloads is reached the oldest forceloaded block will be removed.

The settings for controlling this and their defaults are:

```
dynamic_forceload_active_limit = 8
dynamic_forceload_rotation_time = 60
```

The "forceload" privilege is required for a player to be able to make use of this mod.

## Queue advancement

The queue is advanced first by player, then by the locations registered for that player. That means that if there are a large number of players with locations queued then each player will only have at most one loadblock slot allocated to them at any given time. This is in the interests of fairness; a player cannot get more timeslots allocated to them by placing larger numbers of loadblock anchors.

For example, imagine a server where the active_limit is set to 4. Only blocks can be forceloaded at a time. Imagine that there are five players who have placed anchors:

```
Alice - anchor 1
Bob - anchor 2, anchor 3
Carol - anchor 4
David - anchor 5, anchor 6
Eve - anchor 7, anchor 8, anchor 9, anchor 10, anchor 11, anchor 12, anchor 13, anchor 14
```

As the queue advances the following sequence of events will occur:

1. Alice will have the location of anchor 1 forceloaded.
2. Bob will have the location of anchor 2 forceloaded.
3. Carol will have the location of anchor 4 forceloaded.
4. David will have the location of anchor 5 forceloaded.
5. Eve will have the location of anchor 7 forceloaded. Since this exceeds the limit of 4 active forceloads, the oldest anchor - Alice's anchor 1 - will be unloaded.
6. Alice will have anchor 1 forceloaded, Bob will have anchor 2 unloaded.
7. Bob will have anchor 3 forceloaded, and Carol's anchor 4 is unloaded.
8. Carol's anchor 4 is forceloaded and David's anchor 5 is unloaded.
9. David's anchor 6 is forceloaded and Eve's anchor 7 is unloaded.
10. Eve's anchor 8 is forceloaded and Alice's anchor 1 is unloaded.

As you can see, players in this scenario with only one anchor will have that anchor forceloaded 80% of the time. If they have two anchors, however, each of those anchors will only be loaded 40% of the time. And Eve, with her huge list of anchors, will only have each of her anchors forceloaded 10% of the time. In this way each player gets the same slice of forceload resources and can allocate their time as they see fit.

Since it is still possible for a griefer with multiple accounts to slow things down for everyone by having each of his accounts place a forceload block, it is recommended that the "forceload" privilege be given with some restraint. However, this mod greatly limits the damage that rampant forceload anchor placement could potentially cause, making it something that can be given fairly freely.