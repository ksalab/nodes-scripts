#!/bin/bash -e

#Passphrase (password for wallet)
PASSPHRASE=''

#Validator (valoper address)
VALIDATOR=''

#Wallet name
WALLET='node-wallet'

while true; do

  JAILED=$(nibid q staking validator "${VALIDATOR}" --output json | jq -r '.jailed')

  if [ "${JAILED}" = "true" ]; then
    #True
    echo "$(date +%F--%T) Validator is jailed - Status ${JAILED} - Unjail Validator" | tee -a "$HOME"/unjail.log
    {
      echo "${PASSPHRASE}"
    } | nibid tx slashing unjail --from $WALLET --chain-id nibiru-testnet-2 --yes --fees 10000unibi

  else
    #False
    echo "$(date +%F--%T) Validator not jailed - Status ${JAILED}"

  fi

  echo "Sleeping 1 min"
  sleep 1m

done
