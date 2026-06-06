# 06 — Второй сервис: Navidrome + медиа по NFS

> Этап M6. Результат: Navidrome стримит музыкальную коллекцию; под может
> работать на любом узле. Демонстрирует вариант модуля сервиса с медиа-монтированием.

## Почему NFS для больших коллекций

Музыка/медиа слишком велики (и слишком «холодные») для репликации Longhorn —
они остаются на диске медиа-узла. Рассмотренные варианты:

| Вариант | Вердикт |
|---|---|
| **NFS-экспорт + статический PV csi-driver-nfs** | ✅ выбран — монтируется с любого узла, поды мобильны; RO для плееров, позже возможен RWX для Nextcloud |
| hostPath + nodeAffinity | ❌ приваривает под к медиа-узлу — убивает требование мобильности |
| SMB (csi-driver-smb) | запасной вариант, только если шару нужно нативно отдавать и Windows-клиентам; LAN-SMB может жить отдельно |
| Скопировать в Longhorn | ❌ удваивает/утраивает хранилище для write-once данных |

Тяжёлые медиа-нагрузки (SMB-сервер, Nextcloud, боты для транскодинга) могут
остаться *вне кластера* на медиа-узле; кластер монтирует только нужное.

## 1. NFS-экспорт на медиа-узле

```bash
sudo apt install -y nfs-kernel-server
echo '/export/media 192.168.5.0/24(ro,no_subtree_check,all_squash,anonuid=1000,anongid=1000)' \
  | sudo tee -a /etc/exports
# Примонтировать реальную коллекцию в дерево экспорта (переживает ребут через fstab):
echo '/srv/music /export/media/music none bind 0 0' | sudo tee -a /etc/fstab
sudo mkdir -p /export/media/music && sudo mount -a
sudo exportfs -ra && sudo exportfs -v
```

`ro` на уровне экспорта — самая надёжная гарантия для коллекции. Будущая
RW-шара (Nextcloud) получит *свою* строку экспорта с `rw` и отдельным поддеревом.

## 2. Сторона кластера (уже в git)

- `infrastructure/config/media-nfs-pv.yaml` — статический PV `media-music-ro`
  (драйвер `nfs.csi.k8s.io`, `ReadOnlyMany`, опции `ro,nfsvers=4.1`).
  **TODO проверить**: IP сервера совпадает с медиа-узлом.
- `apps/navidrome/` — модуль: PVC Longhorn для `/data`, PVC `music-ro`,
  привязанный к статическому PV, смонтирован read-only в `/music`.

```bash
git push && flux reconcile ks apps --with-source
```

## 3. Проверка

```bash
kubectl -n navidrome get pvc                  # music-ro Bound к media-music-ro
kubectl -n navidrome exec deploy/navidrome -- ls /music | head
curl -v https://navidrome.nb3.me              # LAN; сканирование находит файлы

# Проверка мобильности (само требование):
kubectl -n navidrome get pod -o wide          # запомнить узел
kubectl drain <тот-узел> --ignore-daemonsets --delete-emptydir-data
kubectl -n navidrome get pod -o wide          # переехал на другой узел, стрим работает
kubectl uncordon <тот-узел>
```

(Если Navidrome окажется на самом медиа-узле, NFS смонтируется через loopback —
для RO-трафика такого масштаба это нормально.)

Далее: [07 — Второй узел](07-second-node.md)
