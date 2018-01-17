test_run = require('test_run').new()
test_run:cmd("push filter '.*/init.lua.*[0-9]+: ' to ''")
test_run:cmd("push filter 'lag: .+' to 'lag: <lag>'")
test_run:cmd("push filter 'idle: .+' to 'idle: <idle>'")
netbox = require('net.box')
fiber = require('fiber')

REPLICASET_1 = { 'storage_1_a', 'storage_1_b' }
REPLICASET_2 = { 'storage_2_a', 'storage_2_b' }

test_run:create_cluster(REPLICASET_1, 'main')
test_run:create_cluster(REPLICASET_2, 'main')
test_run:wait_fullmesh(REPLICASET_1)
test_run:wait_fullmesh(REPLICASET_2)

replicaset1_uuid = test_run:eval('storage_1_a', 'box.info.cluster.uuid')[1]
replicaset2_uuid = test_run:eval('storage_2_a', 'box.info.cluster.uuid')[1]
test_run:cmd("push filter '"..replicaset1_uuid.."' to '<replicaset_1>'")
test_run:cmd("push filter '"..replicaset2_uuid.."' to '<replicaset_2>'")
storage_1_a_uuid = test_run:eval('storage_1_a', 'box.info.uuid')[1]
storage_1_b_uuid = test_run:eval('storage_1_b', 'box.info.uuid')[1]
storage_2_a_uuid = test_run:eval('storage_2_a', 'box.info.uuid')[1]
storage_2_b_uuid = test_run:eval('storage_2_b', 'box.info.uuid')[1]
test_run:cmd("push filter '"..storage_1_a_uuid.."' to '<storage_1_a>'")
test_run:cmd("push filter '"..storage_1_b_uuid.."' to '<storage_1_b>'")
test_run:cmd("push filter '"..storage_2_a_uuid.."' to '<storage_2_a>'")
test_run:cmd("push filter '"..storage_2_b_uuid.."' to '<storage_2_b>'")

_ = test_run:cmd("switch storage_1_a")
util = require('util')
vshard.storage.rebalancer_disable()

replicaset1_uuid = test_run:eval('storage_1_a', 'box.info.cluster.uuid')[1]
replicaset2_uuid = test_run:eval('storage_2_a', 'box.info.cluster.uuid')[1]
vshard.storage.info().replicasets[replicaset1_uuid] or vshard.storage.info()
vshard.storage.info().replicasets[replicaset2_uuid] or vshard.storage.info()

-- Sync API
vshard.storage.sync()
util.check_error(vshard.storage.sync, "xxx")
vshard.storage.sync(100500)

vshard.storage.buckets_info()
vshard.storage.bucket_force_create(1)
vshard.storage.buckets_info()
vshard.storage.bucket_force_create(1) -- error
vshard.storage.bucket_force_drop(1)

vshard.storage.buckets_info()
vshard.storage.bucket_force_create(1)
vshard.storage.bucket_force_create(2)
_ = test_run:cmd("switch storage_2_a")
vshard.storage.bucket_force_create(3)
vshard.storage.bucket_force_create(4)
_ = test_run:cmd("switch storage_2_b")
box.cfg{replication_timeout = 0.01}
vshard.storage.info()
test_run:cmd("stop server storage_2_a")
box.cfg{replication_timeout = 0.01}
vshard.storage.info()
test_run:cmd("start server storage_2_a")
test_run:cmd("switch storage_2_a")
fiber = require('fiber')
while #vshard.storage.info().alerts ~= 1 do fiber.sleep(0.1) end
vshard.storage.info()
test_run:cmd("stop server storage_2_b")
vshard.storage.info()
test_run:cmd("start server storage_2_b")
test_run:cmd("switch storage_2_b")
vshard.storage.info()
test_run:cmd("switch storage_2_a")
vshard.storage.info()

_ = test_run:cmd("switch storage_1_a")

test_run:cmd("setopt delimiter ';'")
box.begin()
for customer_id=1,8 do
    local bucket_id = customer_id % 4
    local name = string.format('Customer %d', customer_id)
    box.space.customer:insert({customer_id, bucket_id, name})
    for account_id=customer_id*10,customer_id*10+2 do
        local name = string.format('Account %d', account_id)
        box.space.account:insert({account_id, customer_id, bucket_id,
                                  100, name})
    end
end
box.commit();
test_run:cmd("setopt delimiter ''");

box.space.customer:select()
box.space.account:select()

vshard.storage.bucket_collect(1)
vshard.storage.bucket_collect(2)

customer_lookup(1)
vshard.storage.call(1, 'read', 'customer_lookup', {1})
vshard.storage.call(100500, 'read', 'customer_lookup', {1})

--
-- Test not existing space in bucket data.
--
vshard.storage.bucket_recv(100, 'from_uuid', {{1000, {{1}}}})

--
-- Bucket transfer
--
vshard.storage.bucket_send(1, replicaset2_uuid)
_ = test_run:cmd("switch storage_2_a")
vshard.storage.buckets_info()
_ = test_run:cmd("switch storage_1_a")
vshard.storage.buckets_info()

_ = test_run:cmd("switch default")

test_run:drop_cluster(REPLICASET_2)
test_run:drop_cluster(REPLICASET_1)
test_run:cmd('clear filter')
