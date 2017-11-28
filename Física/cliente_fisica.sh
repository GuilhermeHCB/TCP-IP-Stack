#!/bin/bash

function monta_frame {
    IP_DATA=`cat packet.txt | xxd -p | tr -d \\n`

    #Preamble e start frame delimiter em hexa
    PREAMBLE='55555555555555D5'

    #Ethertype em hexa
    ETHERTYPE='0800'

    #Bytes 11-14 do pacote IP
    IPORG_OCT1=`echo $((16#$(echo $IP_DATA | cut -b25-26)))`
    IPORG_OCT2=`echo $((16#$(echo $IP_DATA | cut -b27-28)))`
    IPORG_OCT3=`echo $((16#$(echo $IP_DATA | cut -b29-30)))`
    IPORG_OCT4=`echo $((16#$(echo $IP_DATA | cut -b31-32)))`
    IPORG=`echo -n "${IPORG_OCT1}.${IPORG_OCT2}.${IPORG_OCT3}.${IPORG_OCT4}"`
    echo "IP de Origem: $IPORG"

    #Bytes 15-18 do pacote IP
    IPDST_OCT1=`echo $((16#$(echo $IP_DATA | cut -b33-34)))`
    IPDST_OCT2=`echo $((16#$(echo $IP_DATA | cut -b35-36)))`
    IPDST_OCT3=`echo $((16#$(echo $IP_DATA | cut -b37-38)))`
    IPDST_OCT4=`echo $((16#$(echo $IP_DATA | cut -b39-40)))`
    IPDST=`echo "${IPDST_OCT1}.${IPDST_OCT2}.${IPDST_OCT3}.${IPDST_OCT4}"`
    echo "IP de Destino: $IPDST"

    #Pegar o MAC da ORIGEM
    ifconfig > ifc.txt

    while read line; do
        for i in $(echo $line | tr " " "\n")
        do
            if [ "$var" = "1" ]; then
                MAC=$i
                var=2
            fi

            if [ "$i" = "HW" ]; then
                var=1
            fi

            if [ "$var" = "2" ]; then
                var=3
            fi

            if [ "$var" = "3" ] && [ "$i" = "$IPORG" ]; then
                MAC_ORG=`echo $MAC`
            fi
        done
    done < ifc.txt

    rm ifc.txt

    #Se não encontrar o MAC de origem
    if [ -z "$MAC_ORG" ]; then
        MAC_ORG="00:00:00:00:00:00"
    fi

    echo "MAC da Origem: $MAC_ORG"

    #Ping para poder fazer o ARP
    ping -c 1 $IPDST &>/dev/null
    MAC_DST=`arp $IPDST | grep -E -o -e "([A-Za-z0-9]{2}:?){6}"`

    #Se não encontrar o MAC de destino
    if [ -z "$MAC_DST" ]; then
        MAC_DST="00:00:00:00:00:00"
    fi

    echo "MAC do Destino: $MAC_DST"

    #Remover os ':' dos endreços físicos
    MAC_ORG=`echo $MAC_ORG | sed "s/://g"`
    MAC_DST=`echo $MAC_DST | sed "s/://g"`

    #Montar o quadro Ethernet
    echo -n "${PREAMBLE}${MAC_DST}${MAC_ORG}${ETHERTYPE}${IP_DATA}" > frame_e.hex

    #Transfroma o quadro de hexa textual para binário
    xxd -r -p frame_e.hex > frame_e.dat

    #Calcula o CRC e adiciona no final do quadro
    crc32 frame_e.dat | xxd -r -p >> frame_e.dat

    #Transforma o quadro de binário para binário textual
    xxd -b frame_e.dat | cut -d" " -f 2-7 | tr -d \\n | sed "s/ //g" > frame_e.txt

    rm frame_e.hex &> /dev/null
    rm frame_e.dat &> /dev/null
}

#Porta do cliente
PORT_REDE=`echo -n $1`

#Informações da Entidade Par
IP_SERVER=`echo -n $2`
PORT_SERVER=`echo -n $3`

#Se não informar a porta
if [ -z "$PORT_REDE" ]; then
    echo "A porta da camada de rede deve ser informada"
    exit
fi

#Se não informar o IP_SERVER
if [ -z "$IP_SERVER" ]; then
    echo "O IP do servidor deve ser informado"
    exit
fi

#Se não informar o PORT_SERVER
if [ -z "$PORT_SERVER" ]; then
    echo "A porta do servidor deve ser informada"
    exit
fi

while true; do
    #Aguarda conexão da camada superior
    echo "Esperando pacote IP..."
    nc -l $PORT_REDE > packet.txt

    echo "Montando o frame..."
    monta_frame

    #Exibe o pacote IP no formato HEX Dump
    echo "Enviando o pacote IP:"
    xxd packet.txt

    while true; do
        #Envia o quadro Ethernet no formato binário textual para o servidor da camada física
        nc $IP_SERVER $PORT_SERVER < frame_e.txt

        if [ $? -eq 0 ]; then
            break;
        fi

        echo -n "."
        sleep 1
    done

    rm frame_e.txt &> /dev/null
    rm packet.txt &> /dev/null
done