for vm in $(virsh list --state-running --name); do
    echo -n "VM $vm: "
    virsh qemu-agent-command "$vm" '{"execute":"guest-info"}' &>/dev/null \
        && echo "Agent is RUNNING" \
        || echo "Agent is NOT RESPONDING / NOT INSTALLED"
done
