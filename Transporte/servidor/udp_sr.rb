require "#{File.expand_path(__FILE__)}/../../tcp"

if ARGV.length < 2 then
    puts "Parâmetros insuficientes!"
    exit
end 

fscl_port = ARGV[0].to_i
fssr_port = ARGV[1].to_i

while true
    
    puts "Esperando dados da camada física..."
    
    begin

        segmento = recv_socket(fssr_port)

        puts "Segmento recebido..."

        segmento = segmento[20..-1]
        udp = segmento[0..8]
        dados = udp.unpack('nnnn')
        msg = segmento[8..-1]

        puts "Validação do segmento... "

        if checksum(dados.pack('nnn') << msg) == dados[3] then
            puts "OK"
        else
            puts "Segmento ignorado"
        end

        puts "Enviando mensagem para a aplicação..."

        socket = Socket.new Socket::AF_INET, Socket::SOCK_STREAM

        if socket == false then
            puts "Socket falhou."
            break
        end

        connection = socket.connect(Socket.sockaddr_in(dados[1], 'localhost'))

        if connection == false then
            puts "Socket.connect falhou."
            break
        end

        socket.write(msg)
        
        puts "Esperando resposta..."

        msg = socket.read
        break if msg == false

        socket.close

        temp = dados[1]
        porta_ds = dados[0]
        porta_sr = temp

        length = msg.length + 8
        aux = [porta_sr,porta_ds,length]
        checksum = checksum(aux.pack('nnn') << msg)
        aux = [porta_sr,porta_ds,length, checksum]
        segmento = aux.pack('nnnn')
        segmento = segmento << msg

        puts "Porta de Origem: #{porta_sr}"
        puts "Porta de Destino: #{porta_sr}"
        puts "Tamanho: #{length}"
        puts "Checksum: #{checksum}"

        puts "Enviando dados para a camada física..."

        send_socket(segmento, fscl_port)

    rescue Exception => msg
        puts "Error: #{msg}."
        break
    end
end